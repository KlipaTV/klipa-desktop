import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_theme.dart';
import '../../core/security/network_policy.dart';
import '../../core/security/sensitive_data_redactor.dart';
import '../../domain/channel.dart';

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
  var _opening = false;
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
    });
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
        setState(() {
          _error = const SensitiveDataRedactor().text(message);
          _opening = false;
        });
      });

      // libmpv embeds with config loading off by default. These properties also
      // keep URL extractors and script discovery disabled before any media opens.
      final nativePlayer = player.platform;
      if (nativePlayer is! NativePlayer) {
        throw StateError('Klipa Player requires the native playback backend.');
      }
      await nativePlayer.setProperty('ytdl', 'no');
      await nativePlayer.setProperty('load-scripts', 'no');
      _videoController ??= VideoController(player);
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
      });
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    if (channel == null) {
      return const _EmptyPlayer();
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoController case final controller?)
            Video(
              controller: controller,
              controls: NoVideoControls,
              fill: Colors.black,
            ),
          if (_videoController == null || _opening)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          if (_error case final error?)
            _PlayerError(message: error, onRetry: () => _open(channel)),
          Align(
            alignment: Alignment.bottomCenter,
            child: _PlayerControls(player: _player, channel: channel),
          ),
        ],
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

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.player, required this.channel});

  final Player? player;
  final Channel channel;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.92)],
      ),
    ),
    child: Row(
      children: [
        if (player case final current?)
          StreamBuilder<bool>(
            stream: current.stream.playing,
            initialData: current.state.playing,
            builder: (context, snapshot) => IconButton(
              tooltip: snapshot.data == true ? 'Pause' : 'Play',
              onPressed: current.playOrPause,
              icon: Icon(
                snapshot.data == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: KlipaColors.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'LIVE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
