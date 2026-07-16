import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/local_epg_service.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  test(
    'derives Xtream XMLTV and contacts only the configured provider',
    () async {
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.requestedUri);
        request.response
          ..headers.contentType = ContentType('application', 'xml')
          ..write('''
          <tv>
            <programme channel="provider.guide" start="20260716110000 +0000"
                stop="20260716130000 +0000">
              <title>Provider programme</title>
            </programme>
          </tv>
        ''');
        await request.response.close();
      });
      final now = DateTime.utc(2026, 7, 16, 12);

      final result = await LocalEpgService().refresh(
        source: _source(
          kind: PlaylistSourceKind.xtream,
          location: 'http://127.0.0.1:${server.port}',
        ),
        username: 'fixture-user',
        password: 'fixture-password',
        nowUtc: now,
      );

      expect(requests, hasLength(1));
      expect(requests.single.path, '/xmltv.php');
      expect(requests.single.queryParameters['username'], 'fixture-user');
      expect(requests.single.queryParameters['password'], 'fixture-password');
      expect(result.programmes.single.title, 'Provider programme');
      expect(result.refreshedAt, now);
      expect(result.expiresAt, now.add(LocalEpgService.cacheLifetime));
    },
  );

  test('uses an explicitly attached M3U guide without discovery', () async {
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.write('''
        <tv>
          <programme channel="one" start="20260716120000 +0000"
              stop="20260716123000 +0000"><title>One</title></programme>
        </tv>
      ''');
      await request.response.close();
    });

    final result = await LocalEpgService().refresh(
      source: _source(
        kind: PlaylistSourceKind.remoteUrl,
        location: 'https://playlist.invalid/list.m3u',
      ),
      attachedGuideUri: Uri.parse(
        'http://127.0.0.1:${server.port}/user-guide.xml',
      ),
      nowUtc: DateTime.utc(2026, 7, 16, 12),
    );

    expect(paths, ['/user-guide.xml']);
    expect(result.programmes.single.guideId, 'one');
  });

  test('does not guess a guide endpoint for M3U sources', () async {
    await expectLater(
      LocalEpgService().refresh(
        source: _source(
          kind: PlaylistSourceKind.remoteUrl,
          location: 'https://playlist.invalid/list.m3u',
        ),
        nowUtc: DateTime.utc(2026, 7, 16, 12),
      ),
      throwsA(isA<EpgConfigurationException>()),
    );
  });
}

PlaylistSource _source({
  required PlaylistSourceKind kind,
  required String location,
}) => PlaylistSource(
  id: 'source-1',
  name: 'Provider',
  kind: kind,
  location: location,
  allowsPrivateNetwork: true,
  importedAt: DateTime.utc(2026, 7, 16),
);
