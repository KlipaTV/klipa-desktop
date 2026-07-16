import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test(
    'loads and disposes the native media backend with restricted protocols',
    () async {
      MediaKit.ensureInitialized();
      final player = Player(
        configuration: const PlayerConfiguration(
          vo: 'null',
          title: 'Klipa Player native smoke test',
          protocolWhitelist: ['tcp', 'tls', 'http', 'https', 'crypto'],
        ),
      );
      final nativePlayer = player.platform;
      expect(nativePlayer, isA<NativePlayer>());
      final native = nativePlayer! as NativePlayer;
      await native.setProperty('ytdl', 'no');
      await native.setProperty('load-scripts', 'no');
      await native.setProperty('load-unsafe-playlists', 'no');
      await native.setProperty('autoload-files', 'no');
      await native.setProperty('cookies', 'no');
      await native.setProperty('tls-verify', 'yes');
      await native.setProperty('network-timeout', '30');
      await player.dispose();
    },
    skip: Platform.isWindows ? false : 'This validates the Windows bundle.',
  );
}
