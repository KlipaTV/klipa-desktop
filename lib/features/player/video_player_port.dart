import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/channel.dart';

typedef VideoPlayerPortFactory = VideoPlayerPort Function();

abstract interface class VideoPlayerPort {
  Stream<String> get errors;

  Stream<bool> get playingChanges;

  Stream<bool> get bufferingChanges;

  bool get playing;

  bool get buffering;

  Widget buildView({required BoxFit fit});

  Future<void> open(Channel channel);

  Future<void> playOrPause();

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

VideoPlayerPort createMediaKitVideoPlayerPort() => MediaKitVideoPlayerPort();

final class MediaKitVideoPlayerPort implements VideoPlayerPort {
  MediaKitVideoPlayerPort() {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Klipa Player',
        bufferSize: 24 * 1024 * 1024,
        protocolWhitelist: ['tcp', 'tls', 'http', 'https', 'crypto'],
      ),
    );
    _videoController = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _videoController;
  var _hardened = false;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Stream<bool> get playingChanges => _player.stream.playing;

  @override
  Stream<bool> get bufferingChanges => _player.stream.buffering;

  @override
  bool get playing => _player.state.playing;

  @override
  bool get buffering => _player.state.buffering;

  @override
  Widget buildView({required BoxFit fit}) => Video(
    controller: _videoController,
    controls: NoVideoControls,
    fill: Colors.black,
    fit: fit,
  );

  @override
  Future<void> open(Channel channel) async {
    if (!_hardened) {
      final nativePlayer = _player.platform;
      if (nativePlayer is! NativePlayer) {
        throw StateError('Klipa Player requires the native playback backend.');
      }
      await nativePlayer.setProperty('ytdl', 'no');
      await nativePlayer.setProperty('load-scripts', 'no');
      await nativePlayer.setProperty('load-unsafe-playlists', 'no');
      await nativePlayer.setProperty('autoload-files', 'no');
      await nativePlayer.setProperty('cookies', 'no');
      await nativePlayer.setProperty('tls-verify', 'yes');
      await nativePlayer.setProperty('network-timeout', '30');
      _hardened = true;
    }
    await _player.open(
      Media(channel.streamUri.toString(), httpHeaders: channel.httpHeaders),
    );
  }

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
