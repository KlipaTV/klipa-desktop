import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/playlist_import_service.dart';
import 'package:klipa_player_windows/data/xtream_client.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  test(
    'loads only live Xtream data and builds playable channel URLs',
    () async {
      const username = 'fixture-user';
      const password = 'fixture-password';
      final actions = <String?>[];
      server.listen((request) async {
        if (request.uri.path == '/get.php') {
          expect(request.uri.queryParameters['username'], username);
          expect(request.uri.queryParameters['password'], password);
          expect(request.uri.queryParameters['type'], 'm3u_plus');
          expect(request.uri.queryParameters['output'], 'mpegts');
          request.response
            ..headers.contentType = ContentType('audio', 'x-mpegurl')
            ..write('''#EXTM3U
#EXTINF:-1,Fixture News
http://media.example/custom/$username/$password/42.m3u8
''');
          await request.response.close();
          return;
        }
        expect(request.uri.path, '/player_api.php');
        expect(request.uri.queryParameters['username'], username);
        expect(request.uri.queryParameters['password'], password);
        final action = request.uri.queryParameters['action'];
        actions.add(action);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(switch (action) {
            null => {
              'user_info': {'auth': 1, 'status': 'Active'},
            },
            'get_live_categories' => [
              {'category_id': '7', 'category_name': 'News'},
            ],
            'get_live_streams' => [
              {
                'stream_id': 42,
                'name': 'Fixture News',
                'category_id': '7',
                'container_extension': 'm3u8',
                'epg_channel_id': 'fixture.news',
                'stream_icon': 'https://images.example/fixture.png',
              },
            ],
            _ => throw StateError('Unexpected Xtream action: $action'),
          }),
        );
        await request.response.close();
      });

      final result = await PlaylistImportService().fromXtream(
        server: Uri.parse('http://127.0.0.1:${server.port}/'),
        username: username,
        password: password,
        allowPrivateNetwork: true,
      );

      expect(actions.toSet(), {
        null,
        'get_live_categories',
        'get_live_streams',
      });
      expect(result.channels, hasLength(1));
      expect(result.source.kind, PlaylistSourceKind.xtream);
      expect(result.source.location, 'http://127.0.0.1:${server.port}');
      expect(result.source.location, isNot(contains(username)));
      expect(result.source.location, isNot(contains(password)));
      final channel = result.channels.single;
      expect(channel.name, 'Fixture News');
      expect(channel.group, 'News');
      expect(channel.guideId, 'fixture.news');
      expect(channel.streamUri.pathSegments, [
        'custom',
        username,
        password,
        '42.m3u8',
      ]);
      expect(channel.allowsPrivateNetwork, isTrue);
    },
  );

  test('rejects inactive accounts without returning credentials', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'user_info': {'auth': 1, 'status': 'Expired'},
        }),
      );
      await request.response.close();
    });

    await expectLater(
      XtreamClient().loadLiveChannels(
        server: Uri.parse('http://127.0.0.1:${server.port}'),
        username: 'fixture-user',
        password: 'fixture-password',
        allowPrivateNetwork: true,
      ),
      throwsA(
        isA<XtreamException>()
            .having((error) => error.message, 'message', contains('expired'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('fixture-password')),
            ),
      ),
    );
  });
}
