import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/network/bounded_http_client.dart';
import 'package:klipa_player_windows/core/security/network_policy.dart';

class _FixedAddressPolicy extends NetworkPolicy {
  const _FixedAddressPolicy(this.addresses);

  final List<InternetAddress> addresses;

  @override
  Future<List<InternetAddress>> resolveHttpTarget(
    Uri uri, {
    required bool allowPrivateNetwork,
  }) async => addresses;
}

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

  test('downloads a provider guide through the same bounded client', () async {
    server.listen((request) async {
      request.response
        ..headers.contentType = ContentType('application', 'xml')
        ..write('<tv></tv>');
      await request.response.close();
    });

    final bytes = await BoundedHttpClient().getGuide(
      Uri.parse('http://127.0.0.1:${server.port}/guide.xml'),
      allowPrivateNetwork: true,
    );

    expect(String.fromCharCodes(bytes), '<tv></tv>');
  });

  test('rejects a non-success status', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
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
          contains('403'),
        ),
      ),
    );
  });

  test('stops following redirects past the limit', () async {
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${server.port}/again',
        );
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
          contains('redirected too many times'),
        ),
      ),
    );
  });

  test('falls back to the next classified address when one is dead', () async {
    server.listen((request) async {
      request.response
        ..headers.contentType = ContentType('audio', 'x-mpegurl')
        ..write('#EXTM3U\n');
      await request.response.close();
    });

    // First address is a loopback with nothing listening on the server port
    // (fast connection refusal); the client must try the second, live one.
    final client = BoundedHttpClient(
      networkPolicy: _FixedAddressPolicy([
        InternetAddress('127.0.0.2'),
        InternetAddress('127.0.0.1'),
      ]),
    );

    final bytes = await client.getPlaylist(
      Uri.parse('http://provider.example:${server.port}/list.m3u'),
      allowPrivateNetwork: true,
    );

    expect(String.fromCharCodes(bytes), startsWith('#EXTM3U'));
  });

  test('aborts a body that grows past the byte limit', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'x-mpegurl');
      final megabyte = List<int>.filled(1024 * 1024, 0x23);
      for (var i = 0; i < 30; i++) {
        request.response.add(megabyte);
      }
      await request.response.close();
    });

    await expectLater(
      BoundedHttpClient().getPlaylist(
        Uri.parse('http://127.0.0.1:${server.port}/big.m3u'),
        allowPrivateNetwork: true,
      ),
      throwsA(
        isA<PlaylistDownloadException>().having(
          (error) => error.message,
          'message',
          contains('MiB limit'),
        ),
      ),
    );
  });
}
