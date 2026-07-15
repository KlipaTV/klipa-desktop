import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/network/bounded_http_client.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  test(
    'downloads a bounded playlist from an explicitly allowed LAN host',
    () async {
      server.listen((request) async {
        request.response
          ..headers.contentType = ContentType('audio', 'x-mpegurl')
          ..write('#EXTM3U\n#EXTINF:-1,One\nhttps://example.com/live\n');
        await request.response.close();
      });

      final bytes = await BoundedHttpClient().getPlaylist(
        Uri.parse('http://127.0.0.1:${server.port}/list.m3u'),
        allowPrivateNetwork: true,
      );

      expect(String.fromCharCodes(bytes), startsWith('#EXTM3U'));
    },
  );

  test('rejects HTML responses', () async {
    server.listen((request) async {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html>not a playlist</html>');
      await request.response.close();
    });

    await expectLater(
      BoundedHttpClient().getPlaylist(
        Uri.parse('http://127.0.0.1:${server.port}/list.m3u'),
        allowPrivateNetwork: true,
      ),
      throwsA(
        isA<PlaylistDownloadException>().having(
          (error) => error.message,
          'message',
          contains('web page'),
        ),
      ),
    );
  });
}
