import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/m3u_parser.dart';

void main() {
  const parser = M3uParser();

  test('parses supported channel metadata and safe headers', () {
    final input = '''#EXTM3U
#EXTINF:-1 tvg-id="one" tvg-logo="https://img.example/one.png" group-title="News",Channel One
#EXTVLCOPT:http-user-agent=Klipa Test
#EXTVLCOPT:http-origin=https://provider.example
https://stream.example/live/one.m3u8
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels, hasLength(1));
    final channel = result.channels.single;
    expect(channel.name, 'Channel One');
    expect(channel.guideId, 'one');
    expect(channel.group, 'News');
    expect(channel.logoUri, Uri.parse('https://img.example/one.png'));
    expect(channel.httpHeaders, {
      'User-Agent': 'Klipa Test',
      'Origin': 'https://provider.example',
    });
    expect(channel.allowsPrivateNetwork, isFalse);
  });

  test('drops privileged headers and unsupported stream schemes', () {
    final input = '''#EXTM3U
#EXTINF:-1,Unsafe
#EXTVLCOPT:http-cookie=session-secret
#EXTVLCOPT:http-authorization=Bearer secret
file:///C:/secret.ts
#EXTINF:-1,Safe
https://stream.example/live
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels, hasLength(1));
    expect(result.channels.single.name, 'Safe');
    expect(result.channels.single.httpHeaders, isEmpty);
    expect(result.warnings, hasLength(1));
  });

  test('rejects embedded credentials', () {
    final input = '''#EXTM3U
#EXTINF:-1,Unsafe
https://user:password@stream.example/live
''';

    expect(
      () => parser.parse(
        Uint8List.fromList(utf8.encode(input)),
        sourceId: 'source',
        allowPrivateNetwork: false,
      ),
      throwsA(isA<PlaylistFormatException>()),
    );
  });

  test('rejects overlong lines before creating channels', () {
    final longLine = List.filled(M3uParser.maxLineLength + 1, 'a').join();
    final input = '#EXTM3U\n$longLine';

    expect(
      () => parser.parse(
        Uint8List.fromList(utf8.encode(input)),
        sourceId: 'source',
        allowPrivateNetwork: false,
      ),
      throwsA(
        isA<PlaylistFormatException>().having(
          (error) => error.message,
          'message',
          contains('64 KiB'),
        ),
      ),
    );
  });
}
