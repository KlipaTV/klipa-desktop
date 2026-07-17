import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/m3u_parser.dart';
import 'package:klipa_player_windows/data/playlist_import_service.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';

void main() {
  late HttpServer server;
  var requestCount = 0;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requestCount = 0;
    server.listen((request) async {
      requestCount++;
      request.response
        ..headers.contentType = ContentType('audio', 'x-mpegurl')
        ..write('''#EXTM3U
#EXTINF:-1 group-title="News",Version $requestCount
https://stream.example/live/$requestCount.ts
''');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('remote source identity is stable when playlist bytes change', () async {
    final uri = Uri.parse('http://127.0.0.1:${server.port}/list.m3u');
    final importer = PlaylistImportService();

    final first = await importer.fromUrl(uri, allowPrivateNetwork: true);
    final second = await importer.fromUrl(uri, allowPrivateNetwork: true);

    expect(first.source.id, second.source.id);
    expect(first.channels.single.name, 'Version 1');
    expect(second.channels.single.name, 'Version 2');
  });

  test('refresh preserves an existing source identity and name', () async {
    final importedAt = DateTime.utc(2026, 7, 15);
    final source = PlaylistSource(
      id: 'legacy-stable-id',
      name: 'My renamed source',
      kind: PlaylistSourceKind.remoteUrl,
      location: 'http://127.0.0.1:${server.port}/list.m3u',
      allowsPrivateNetwork: true,
      importedAt: importedAt,
    );

    final result = await PlaylistImportService().refresh(source);

    expect(result.source.id, source.id);
    expect(result.source.name, source.name);
    expect(result.source.importedAt, importedAt);
    expect(result.channels.single.sourceId, source.id);
  });

  test('refresh rejects a corrupt stored playlist address', () async {
    final source = PlaylistSource(
      id: 'source-1',
      name: 'Broken',
      kind: PlaylistSourceKind.remoteUrl,
      location: 'http://[invalid',
      allowsPrivateNetwork: false,
      importedAt: DateTime.utc(2026, 7, 15),
    );

    await expectLater(
      PlaylistImportService().refresh(source),
      throwsA(
        isA<PlaylistFormatException>().having(
          (error) => error.message,
          'message',
          contains('Re-add'),
        ),
      ),
    );
  });
}
