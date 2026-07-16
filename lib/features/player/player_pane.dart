import 'dart:async';

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
    this.controller,
    this.windowController = const MethodChannelAppWindowController(),
    this.playerFactory = createMediaKitVideoPlayerPort,
    this.channelStartTimeout = const Duration(seconds: 20),
    this.openCommandTimeout = const Duration(seconds: 5),
    this.readinessGrace = const Duration(milliseconds: 500),
    super.key,
  });

  final Channel? channel;
  final Channel? resumeChannel;
  final VoidCallback? onResume;
  final PlayerPaneController? controller;
  final AppWindowController windowController;
  final VideoPlayerPortFactory playerFactory;
  final Duration channelStartTimeout;
  final Duration openCommandTimeout;
  final Duration readinessGrace;

  @override
  State<PlayerPane> createState() => _PlayerPaneState();
}

class _PlayerPaneState extends State<PlayerPane> {
  static const _startTimeoutMessage =
      'The channel did not start in time. You can try again.';

  VideoPlayerPort? _player;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  final _focusNode = FocusNode(debugLabel: 'Player');
  Timer? _hideControlsTimer;
  Timer? _channelStartTimer;
  Timer? _readinessTimer;
  Future<void> _openQueue = Future.value();
  Future<void> _playerDisposal = Future.value();
  var _openGeneration = 0;
  var _opening = false;
  var _playing = false;
  var _buffering = false;
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
    if (widget.channel case final channel?) _requestOpen(channel);
  }

  @override
  void didUpdateWidget(PlayerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(_stopCallback);
      widget.controller?._attach(_stopCallback);
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

  void _requestOpen(Channel channel) {
    final generation = ++_openGeneration;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    setState(() {
      _opening = true;
      _buffering = true;
      _playing = false;
      _error = null;
      _controlsVisible = true;
    });
    _channelStartTimer = Timer(
      widget.channelStartTimeout,
      () => _failCurrent(generation, _startTimeoutMessage),
    );
    _openQueue = _openQueue.then((_) => _performOpen(channel, generation));
  }

  Future<void> _stopPlayer() {
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    if (mounted) {
      setState(() {
        _opening = false;
        _playing = false;
        _buffering = false;
        _error = null;
        _controlsVisible = true;
      });
    }
    _openQueue = _openQueue.then((_) => _disposeCurrentPlayer());
    return _openQueue;
  }

  Future<void> _performOpen(Channel channel, int generation) async {
    try {
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
      _failCurrent(generation, _startTimeoutMessage);
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
    _failCurrent(generation, PlaybackErrorMapper.userMessage(message));
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
      setState(() {
        _opening = false;
        _controlsVisible = true;
      });
      _scheduleControlsHide();
    });
  }

  void _failCurrent(int generation, String message) {
    if (!mounted || generation != _openGeneration) return;
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    final player = _player;
    setState(() {
      _opening = false;
      _playing = false;
      _buffering = false;
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
  }

  List<Future<void>> _detachPlayerSubscriptions() {
    final subscriptions = [
      _errorSubscription,
      _playingSubscription,
      _bufferingSubscription,
    ];
    _errorSubscription = null;
    _playingSubscription = null;
    _bufferingSubscription = null;
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
    final disposal = player.dispose();
    _playerDisposal = disposal;
    await disposal;
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    widget.controller?._detach(_stopCallback);
    _openGeneration++;
    _cancelStartTimers();
    _hideControlsTimer?.cancel();
    unawaited(_errorSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_player?.dispose());
    _player = null;
    if (_fullscreen) unawaited(widget.windowController.setFullscreen(false));
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    if (channel == null) {
      return _EmptyPlayer(
        resumeChannel: widget.resumeChannel,
        onResume: widget.onResume,
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
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) _revealControls();
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
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
