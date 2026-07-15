import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_theme.dart';
import '../../core/security/network_policy.dart';
import '../../core/security/sensitive_data_redactor.dart';
import '../../domain/channel.dart';
import 'playback_control_bar.dart';

class PlayerPane extends StatefulWidget {
  const PlayerPane({required this.channel, super.key});

  final Channel? channel;

  @override
  State<PlayerPane> createState() => _PlayerPaneState();
}

class _PlayerPaneState extends State<PlayerPane> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  final _focusNode = FocusNode(debugLabel: 'Player');
  Timer? _hideControlsTimer;
  var _opening = false;
  var _playing = false;
  var _controlsVisible = true;
  var _muted = false;
  var _volume = 100.0;
  var _fit = BoxFit.contain;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.channel != null) unawaited(_open(widget.channel!));
  }

  @override
  void didUpdateWidget(PlayerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channel?.id != oldWidget.channel?.id && widget.channel != null) {
      unawaited(_open(widget.channel!));
    }
  }

  Future<void> _open(Channel channel) async {
    setState(() {
      _opening = true;
      _error = null;
      _controlsVisible = true;
    });
    _hideControlsTimer?.cancel();
    try {
      await const NetworkPolicy().validateHttpTarget(
        channel.streamUri,
        allowPrivateNetwork: channel.allowsPrivateNetwork,
      );
      MediaKit.ensureInitialized();
      final player = _player ??= Player(
        configuration: const PlayerConfiguration(
          title: 'Klipa Player',
          bufferSize: 24 * 1024 * 1024,
          protocolWhitelist: ['tcp', 'tls', 'http', 'https', 'crypto'],
        ),
      );
      await _errorSubscription?.cancel();
      _errorSubscription = player.stream.error.listen((message) {
        if (!mounted) return;
        _hideControlsTimer?.cancel();
        setState(() {
          _error = const SensitiveDataRedactor().text(message);
          _opening = false;
          _controlsVisible = true;
        });
      });
      await _playingSubscription?.cancel();
      _playingSubscription = player.stream.playing.listen(_handlePlaying);

      // libmpv embeds with config loading off by default. These properties also
      // keep URL extractors and script discovery disabled before any media opens.
      final nativePlayer = player.platform;
      if (nativePlayer is! NativePlayer) {
        throw StateError('Klipa Player requires the native playback backend.');
      }
      await nativePlayer.setProperty('ytdl', 'no');
      await nativePlayer.setProperty('load-scripts', 'no');
      _videoController ??= VideoController(player);
      await player.setVolume(_muted ? 0 : _volume);
      await player.open(
        Media(channel.streamUri.toString(), httpHeaders: channel.httpHeaders),
      );
      if (!mounted || widget.channel?.id != channel.id) return;
      setState(() => _opening = false);
    } on Object catch (error) {
      if (!mounted || widget.channel?.id != channel.id) return;
      setState(() {
        _opening = false;
        _error = const SensitiveDataRedactor().text(error.toString());
        _controlsVisible = true;
      });
    }
  }

  void _handlePlaying(bool playing) {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    setState(() {
      _playing = playing;
      _controlsVisible = true;
    });
    if (playing) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_playing || _error != null) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _revealControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (_playing) _scheduleControlsHide();
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

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    unawaited(_errorSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_player?.dispose());
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    if (channel == null) {
      return const _EmptyPlayer();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      },
      child: Focus(
        focusNode: _focusNode,
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
                  if (_videoController case final controller?)
                    Video(
                      controller: controller,
                      controls: NoVideoControls,
                      fill: Colors.black,
                      fit: _fit,
                    ),
                  if (_videoController == null || _opening)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_error case final error?)
                    _PlayerError(message: error, onRetry: () => _open(channel)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: PlaybackControlBar(
                          channelName: channel.name,
                          playing: _playing,
                          muted: _muted,
                          volume: _muted ? 0 : _volume,
                          fit: _fit,
                          onPlayPause: _player == null ? null : _togglePlayback,
                          onMute: _player == null ? null : _toggleMute,
                          onVolumeChanged: _player == null ? null : _setVolume,
                          onFitChanged: _toggleFit,
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
  const _EmptyPlayer();

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
