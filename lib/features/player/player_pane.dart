import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/security/network_policy.dart';
import '../../core/security/sensitive_data_redactor.dart';
import '../../domain/channel.dart';
import '../../platform/app_window_controller.dart';
import 'playback_control_bar.dart';
import 'playback_error_mapper.dart';
import 'video_player_port.dart';

final class PlayerPaneController {
  Future<void> Function()? _stop;

  Future<void> stop() => _stop?.call() ?? Future<void>.value();

  void _attach(Future<void> Function() stop) => _stop = stop;

  void _detach(Future<void> Function() stop) {
    if (identical(_stop, stop)) _stop = null;
  }
}

class PlayerPane extends StatefulWidget {
  const PlayerPane({
    required this.channel,
    this.resumeChannel,
    this.onResume,
    this.onFullscreenChanged,
    this.onPreviousChannel,
    this.onNextChannel,
    this.controller,
    this.windowController = const MethodChannelAppWindowController(),
    this.playerFactory = createMediaKitVideoPlayerPort,
    this.channelStartTimeout = const Duration(seconds: 20),
    this.openCommandTimeout = const Duration(seconds: 5),
    this.readinessGrace = const Duration(milliseconds: 500),
    this.errorGrace = const Duration(seconds: 2),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectAttempts = 5,
    this.stablePlayback = const Duration(seconds: 20),
    super.key,
  });

  final Channel? channel;
  final Channel? resumeChannel;
  final VoidCallback? onResume;
  final ValueChanged<bool>? onFullscreenChanged;
  final VoidCallback? onPreviousChannel;
  final VoidCallback? onNextChannel;
  final PlayerPaneController? controller;
  final AppWindowController windowController;
  final VideoPlayerPortFactory playerFactory;
  final Duration channelStartTimeout;
  final Duration openCommandTimeout;
  final Duration readinessGrace;

  /// How long a native error may stand before it counts. libmpv reports some
  /// errors (a missing audio device, one bad segment) at error level while the
  /// picture keeps playing; only an error the playback does not outlive fails
  /// the channel.
  final Duration errorGrace;

  /// First wait before reopening a live channel that stopped after it played;
  /// each further attempt doubles it, up to eight times this value, so the
  /// default attempts cover an outage of about half a minute.
  final Duration reconnectDelay;
  final int maxReconnectAttempts;

  /// Uninterrupted playback after which a later drop starts a fresh set of
  /// reconnect attempts.
  final Duration stablePlayback;

  @override
  State<PlayerPane> createState() => _PlayerPaneState();
}

class _PlayerPaneState extends State<PlayerPane> {
  static const _startTimeoutMessage =
      'The channel did not start in time. You can try again.';
  static const _streamLostMessage =
      'The channel stopped and did not come back. You can try again.';

  VideoPlayerPort? _player;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _windowFullscreenSubscription;
  final _focusNode = FocusNode(debugLabel: 'Player');
  Timer? _hideControlsTimer;
  Timer? _channelStartTimer;
  Timer? _readinessTimer;
  Timer? _errorGraceTimer;
  Timer? _reconnectTimer;
  Timer? _stablePlaybackTimer;
  Future<void> _openQueue = Future.value();
  Future<void> _playerDisposal = Future.value();
  var _openGeneration = 0;
  var _opening = false;
  var _playing = false;
  var _buffering = false;
  var _reconnecting = false;
  var _reconnectAttempts = 0;
  // Whether the channel played since it was last chosen. Only a channel that
  // played is reopened on its own; one that never started fails as before.
  var _hadPlayback = false;
  var _controlsVisible = true;
  var _muted = false;
  var _volume = 100.0;
  var _fit = BoxFit.contain;
  var _fullscreen = false;

  late final Future<void> Function() _stopCallback = _stopPlayer;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_stopCallback);
    _listenToWindow();
    if (widget.channel case final channel?) _requestOpen(channel);
  }

  void _listenToWindow() {
    unawaited(_windowFullscreenSubscription?.cancel());
    _windowFullscreenSubscription = widget.windowController.fullscreenChanges
        .listen((fullscreen) {
          if (!mounted || fullscreen == _fullscreen) return;
          setState(() => _fullscreen = fullscreen);
          widget.onFullscreenChanged?.call(fullscreen);
        });
  }

  @override
  void didUpdateWidget(PlayerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(_stopCallback);
      widget.controller?._attach(_stopCallback);
    }
    if (!identical(widget.windowController, oldWidget.windowController)) {
      _listenToWindow();
    }
    if (widget.channel?.id != oldWidget.channel?.id ||
        widget.channel?.sourceId != oldWidget.channel?.sourceId) {
      if (widget.channel case final channel?) {
        _requestOpen(channel);
      } else {
        unawaited(_stopPlayer());
      }
    }
  }

  void _requestOpen(Channel channel, {bool reconnect = false}) {
    final generation = ++_openGeneration;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    if (!reconnect) _resetRecovery();
    setState(() {
      _opening = true;
      _buffering = true;
      _playing = false;
      _reconnecting = reconnect;
      _error = null;
      _controlsVisible = true;
    });
    _channelStartTimer = Timer(
      widget.channelStartTimeout,
      () => _recoverOrFail(channel, generation, _startTimeoutMessage),
    );
    _openQueue = _settled(
      _openQueue,
    ).then((_) => _performOpen(channel, generation));
  }

  Future<void> _stopPlayer() {
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    _resetRecovery();
    if (mounted) {
      setState(() {
        _opening = false;
        _playing = false;
        _buffering = false;
        _reconnecting = false;
        _error = null;
        _controlsVisible = true;
      });
    }
    _openQueue = _settled(_openQueue).then((_) => _disposeCurrentPlayer());
    return _openQueue;
  }

  Future<void> _settled(Future<void> future) async {
    try {
      await future;
    } on Object {
      // Errors are surfaced where they occur; the queue must keep draining.
    }
  }

  Future<void> _performOpen(Channel channel, int generation) async {
    try {
      if (!_isCurrent(channel, generation)) return;
      await const NetworkPolicy().validateHttpTarget(
        channel.streamUri,
        allowPrivateNetwork: channel.allowsPrivateNetwork,
      );
      if (!_isCurrent(channel, generation)) return;

      await _disposeCurrentPlayer();
      if (!_isCurrent(channel, generation)) return;

      final player = widget.playerFactory();
      _player = player;
      _errorSubscription = player.errors.listen(
        (message) => _handlePlayerError(message, channel, generation, player),
      );
      _playingSubscription = player.playingChanges.listen(
        (playing) => _handlePlaying(playing, channel, generation, player),
      );
      _bufferingSubscription = player.bufferingChanges.listen(
        (buffering) => _handleBuffering(buffering, channel, generation, player),
      );
      _completedSubscription = player.completedChanges.listen(
        (completed) => _handleCompleted(completed, channel, generation, player),
      );

      if (mounted) setState(() {});
      await player
          .setVolume(_muted ? 0 : _volume)
          .timeout(widget.openCommandTimeout);
      if (!_isOwnedAndCurrent(player, channel, generation)) {
        await _disposePlayerIfOwned(player);
        return;
      }
      await player.open(channel).timeout(widget.openCommandTimeout);
      if (!_isOwnedAndCurrent(player, channel, generation)) {
        await _disposePlayerIfOwned(player);
        return;
      }
      _handlePlaying(player.playing, channel, generation, player);
      _handleBuffering(player.buffering, channel, generation, player);
    } on TimeoutException {
      _recoverOrFail(channel, generation, _startTimeoutMessage);
    } on NetworkPolicyException catch (error) {
      _failCurrent(
        generation,
        const SensitiveDataRedactor().text(error.toString()),
      );
    } on Object catch (error) {
      _failCurrent(generation, PlaybackErrorMapper.userMessage(error));
    }
  }

  bool _isCurrent(Channel channel, int generation) =>
      mounted &&
      generation == _openGeneration &&
      widget.channel?.id == channel.id &&
      widget.channel?.sourceId == channel.sourceId;

  bool _isOwnedAndCurrent(
    VideoPlayerPort player,
    Channel channel,
    int generation,
  ) => identical(_player, player) && _isCurrent(channel, generation);

  void _handlePlayerError(
    String message,
    Channel channel,
    int generation,
    VideoPlayerPort player,
  ) {
    if (!_isOwnedAndCurrent(player, channel, generation)) return;
    if (_errorGraceTimer != null) return;
    final positionAtError = player.position;
    final userMessage = PlaybackErrorMapper.userMessage(message);
    _errorGraceTimer = Timer(widget.errorGrace, () {
      _errorGraceTimer = null;
      if (!_isOwnedAndCurrent(player, channel, generation)) return;
      // The picture moved on, so the error did not stop playback.
      if (player.position > positionAtError) return;
      _recoverOrFail(channel, generation, userMessage);
    });
  }

  void _handleCompleted(
    bool completed,
    Channel channel,
    int generation,
    VideoPlayerPort player,
  ) {
    if (!completed || !_isOwnedAndCurrent(player, channel, generation)) return;
    // A live channel has no end: the provider closed the stream.
    _recoverOrFail(channel, generation, PlaybackErrorMapper.unavailableMessage);
  }

  void _handlePlaying(
    bool playing,
    Channel channel,
    int generation,
    VideoPlayerPort player,
  ) {
    if (!_isOwnedAndCurrent(player, channel, generation)) return;
    _hideControlsTimer?.cancel();
    setState(() {
      _playing = playing;
      _controlsVisible = true;
    });
    if (playing) {
      _considerReady(channel, generation, player);
    } else {
      _readinessTimer?.cancel();
      _readinessTimer = null;
    }
  }

  void _handleBuffering(
    bool buffering,
    Channel channel,
    int generation,
    VideoPlayerPort player,
  ) {
    if (!_isOwnedAndCurrent(player, channel, generation)) return;
    _hideControlsTimer?.cancel();
    setState(() {
      _buffering = buffering && _error == null;
      _controlsVisible = true;
    });
    if (_buffering) {
      _readinessTimer?.cancel();
      _readinessTimer = null;
    } else {
      _considerReady(channel, generation, player);
    }
  }

  void _considerReady(Channel channel, int generation, VideoPlayerPort player) {
    if (!_isOwnedAndCurrent(player, channel, generation) ||
        !_playing ||
        _buffering ||
        _error != null) {
      return;
    }
    _readinessTimer ??= Timer(widget.readinessGrace, () {
      _readinessTimer = null;
      if (!_isOwnedAndCurrent(player, channel, generation) ||
          !_playing ||
          _buffering ||
          _error != null) {
        return;
      }
      _channelStartTimer?.cancel();
      _channelStartTimer = null;
      _hadPlayback = true;
      _stablePlaybackTimer?.cancel();
      _stablePlaybackTimer = Timer(widget.stablePlayback, () {
        _stablePlaybackTimer = null;
        _reconnectAttempts = 0;
      });
      setState(() {
        _opening = false;
        _reconnecting = false;
        _controlsVisible = true;
      });
      _scheduleControlsHide();
    });
  }

  /// Reopens a channel that stopped after it played, with a doubling wait,
  /// and fails it once the attempts run out. A channel that never played
  /// fails at once, as a first start always has.
  void _recoverOrFail(Channel channel, int generation, String message) {
    if (!mounted || generation != _openGeneration) return;
    if (!_hadPlayback || _reconnectAttempts >= widget.maxReconnectAttempts) {
      _failCurrent(generation, _hadPlayback ? _streamLostMessage : message);
      return;
    }
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    _stablePlaybackTimer?.cancel();
    _stablePlaybackTimer = null;
    final delay = widget.reconnectDelay * (1 << min(_reconnectAttempts, 3));
    _reconnectAttempts++;
    final player = _player;
    setState(() {
      _opening = true;
      _playing = false;
      _buffering = true;
      _reconnecting = true;
      _error = null;
      _controlsVisible = true;
    });
    if (player != null) unawaited(_disposePlayerIfOwned(player));
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!mounted ||
          widget.channel?.id != channel.id ||
          widget.channel?.sourceId != channel.sourceId) {
        return;
      }
      _requestOpen(channel, reconnect: true);
    });
  }

  void _resetRecovery() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stablePlaybackTimer?.cancel();
    _stablePlaybackTimer = null;
    _reconnectAttempts = 0;
    _hadPlayback = false;
  }

  void _failCurrent(int generation, String message) {
    if (!mounted || generation != _openGeneration) return;
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    _resetRecovery();
    final player = _player;
    setState(() {
      _opening = false;
      _playing = false;
      _buffering = false;
      _reconnecting = false;
      _error = message;
      _controlsVisible = true;
    });
    if (player != null) unawaited(_disposePlayerIfOwned(player));
  }

  void _cancelStartTimers() {
    _channelStartTimer?.cancel();
    _channelStartTimer = null;
    _readinessTimer?.cancel();
    _readinessTimer = null;
    _errorGraceTimer?.cancel();
    _errorGraceTimer = null;
  }

  List<Future<void>> _detachPlayerSubscriptions() {
    final subscriptions = [
      _errorSubscription,
      _playingSubscription,
      _bufferingSubscription,
      _completedSubscription,
    ];
    _errorSubscription = null;
    _playingSubscription = null;
    _bufferingSubscription = null;
    _completedSubscription = null;
    return [
      for (final subscription in subscriptions)
        if (subscription != null) subscription.cancel(),
    ];
  }

  Future<void> _disposePlayerIfOwned(VideoPlayerPort player) async {
    if (!identical(_player, player)) return;
    _player = null;
    final subscriptionCancellations = _detachPlayerSubscriptions();
    for (final cancellation in subscriptionCancellations) {
      unawaited(cancellation);
    }
    final disposal = _disposePlayer(player);
    _playerDisposal = disposal;
    await disposal;
    if (mounted) setState(() {});
  }

  Future<void> _disposePlayer(VideoPlayerPort player) async {
    try {
      await player.dispose();
    } on Object {
      // A failed native teardown must not block later playback.
    }
  }

  Future<void> _disposeCurrentPlayer() async {
    final player = _player;
    if (player == null) {
      final subscriptionCancellations = _detachPlayerSubscriptions();
      await _playerDisposal;
      for (final cancellation in subscriptionCancellations) {
        unawaited(cancellation);
      }
      return;
    }
    await _disposePlayerIfOwned(player);
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_playing || _buffering || _error != null) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _revealControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (_playing && !_buffering) _scheduleControlsHide();
  }

  void _togglePlayback() {
    _revealControls();
    if (_player case final player?) unawaited(player.playOrPause());
  }

  void _toggleMute() {
    _revealControls();
    final muted = !_muted;
    if (!muted && _volume == 0) _volume = 50;
    setState(() => _muted = muted);
    if (_player case final player?) {
      unawaited(player.setVolume(muted ? 0 : _volume));
    }
  }

  void _setVolume(double volume) {
    _revealControls();
    setState(() {
      _volume = volume.clamp(0, 100);
      _muted = _volume == 0;
    });
    if (_player case final player?) unawaited(player.setVolume(_volume));
  }

  void _toggleFit() {
    _revealControls();
    setState(() {
      _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    });
  }

  Future<void> _setFullscreen(bool enabled) async {
    _revealControls();
    try {
      final fullscreen = await widget.windowController.setFullscreen(enabled);
      if (!mounted) return;
      setState(() => _fullscreen = fullscreen);
      widget.onFullscreenChanged?.call(fullscreen);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Full screen is unavailable.')),
      );
    }
  }

  void _toggleFullscreen() {
    unawaited(_setFullscreen(!_fullscreen));
  }

  void _exitFullscreen() {
    if (_fullscreen) unawaited(_setFullscreen(false));
  }

  // Up walks the list the way the browser shows it (the channel above); CH+
  // follows the broadcast convention and moves to the next channel.
  static const _previousChannelKeys = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.channelDown,
    LogicalKeyboardKey.mediaTrackPrevious,
  ];

  static const _nextChannelKeys = [
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.mediaTrackNext,
  ];

  void _zap(VoidCallback? change) {
    if (change == null) return;
    _revealControls();
    change();
  }

  @override
  void dispose() {
    widget.controller?._detach(_stopCallback);
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    _resetRecovery();
    unawaited(_errorSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_windowFullscreenSubscription?.cancel());
    if (_player case final player?) unawaited(_disposePlayer(player));
    _player = null;
    if (_fullscreen) {
      unawaited(widget.windowController.setFullscreen(false));
      if (widget.onFullscreenChanged case final onFullscreenChanged?) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onFullscreenChanged(false),
        );
      }
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    if (channel == null) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
          const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
          const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreen,
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _focusNode.requestFocus(),
            child: _EmptyPlayer(
              resumeChannel: widget.resumeChannel,
              onResume: widget.onResume,
            ),
          ),
        ),
      );
    }
    final controlsVisible = shouldShowPlaybackControls(
      requestedVisible: _controlsVisible,
      playing: _playing,
      buffering: _buffering,
      opening: _opening,
      hasError: _error != null,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreen,
        for (final key in _previousChannelKeys)
          SingleActivator(key): () => _zap(widget.onPreviousChannel),
        for (final key in _nextChannelKeys)
          SingleActivator(key): () => _zap(widget.onNextChannel),
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) _revealControls();
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          // The pointer hides with the controls so it never sits on the
          // picture; any movement brings both back.
          cursor: controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _revealControls(),
          child: Listener(
            onPointerDown: (_) {
              _focusNode.requestFocus();
              _revealControls();
            },
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_player case final player?)
                    GestureDetector(
                      onDoubleTap: _toggleFullscreen,
                      child: player.buildView(fit: _fit),
                    ),
                  if (_player == null || _opening)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_error case final error?)
                    _PlayerError(
                      message: error,
                      onRetry: () => _requestOpen(channel),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: !controlsVisible,
                      child: AnimatedOpacity(
                        opacity: controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: PlaybackControlBar(
                          channelName: channel.name,
                          playing: _playing,
                          buffering: _buffering,
                          reconnecting: _reconnecting,
                          showStatus: _error == null,
                          muted: _muted,
                          volume: _muted ? 0 : _volume,
                          fit: _fit,
                          fullscreen: _fullscreen,
                          onPlayPause: _player == null ? null : _togglePlayback,
                          onMute: _player == null ? null : _toggleMute,
                          onVolumeChanged: _player == null ? null : _setVolume,
                          onFitChanged: _toggleFit,
                          onFullscreenChanged: _toggleFullscreen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({this.resumeChannel, this.onResume});

  final Channel? resumeChannel;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline_rounded,
            size: 54,
            color: KlipaColors.foregroundDim.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 14),
          const Text(
            'Choose a channel',
            style: TextStyle(color: KlipaColors.foregroundMuted),
          ),
          if (resumeChannel case final channel?) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('resume-last-channel'),
              onPressed: onResume,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(
                'Resume ${channel.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.88),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}
