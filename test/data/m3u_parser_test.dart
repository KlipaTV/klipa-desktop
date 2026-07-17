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

  test('skips malformed EXTINF entries and their stream lines', () {
    final input = '''#EXTM3U
#EXTINF:-1,One
https://stream.example/one
#EXTINF:-1 tvg-name="Broken,Two
https://stream.example/two
#EXTINF:-1,Three
https://stream.example/three
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels.map((channel) => channel.name), ['One', 'Three']);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single, contains('malformed EXTINF'));
  });

  test('applies directives that precede their EXTINF entry', () {
    final input = '''#EXTM3U
#EXTGRP:Sports
#EXTVLCOPT:http-user-agent=Klipa Test
#EXTINF:-1,One
https://stream.example/one
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    final channel = result.channels.single;
    expect(channel.group, 'Sports');
    expect(channel.httpHeaders, {'User-Agent': 'Klipa Test'});
  });

  test('parses Kodi pipe options into safe headers', () {
    final input = '''#EXTM3U
#EXTINF:-1,One
https://stream.example/one|User-Agent=Klipa Test&Cookie=secret
#EXTINF:-1,Two
https://stream.example/two|nothing-usable
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels, hasLength(2));
    final one = result.channels[0];
    expect(one.streamUri, Uri.parse('https://stream.example/one'));
    expect(one.httpHeaders, {'User-Agent': 'Klipa Test'});
    final two = result.channels[1];
    expect(two.streamUri, Uri.parse('https://stream.example/two'));
    expect(two.httpHeaders, isEmpty);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single, contains('stream options'));
  });

  test('decodes UTF-16LE playlists with a byte order mark', () {
    const input = '#EXTM3U\n#EXTINF:-1,Kanal Bat\nhttps://stream.example/eus\n';
    final bytes = <int>[0xff, 0xfe];
    for (final unit in input.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }

    final result = parser.parse(
      Uint8List.fromList(bytes),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels.single.name, 'Kanal Bat');
  });

  test('caps recorded warnings and summarises the rest', () {
    final input = StringBuffer('#EXTM3U\n');
    for (var index = 0; index < M3uParser.maxWarnings + 10; index++) {
      input.writeln('ftp://skipped.example/$index');
    }
    input
      ..writeln('#EXTINF:-1,One')
      ..writeln('https://stream.example/one');

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input.toString())),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels, hasLength(1));
    expect(result.warnings, hasLength(M3uParser.maxWarnings + 1));
    expect(result.warnings.last, contains('10 more'));
  });

  test('does not leak an abandoned entry\'s headers onto the next', () {
    final input = '''#EXTM3U
#EXTINF:-1,Abandoned
#EXTVLCOPT:http-referrer=https://secret.example/?token=abc
#EXTINF:-1,Real
https://stream.example/real
''';

    final result = parser.parse(
      Uint8List.fromList(utf8.encode(input)),
      sourceId: 'source',
      allowPrivateNetwork: false,
    );

    expect(result.channels, hasLength(1));
    expect(result.channels.single.name, 'Real');
    expect(result.channels.single.httpHeaders, isEmpty);
  });

  test('rejects UTF-16 input with an unpaired trailing byte', () {
    const input = '#EXTM3U\n#EXTINF:-1,One\nhttps://stream.example/one\n';
    final bytes = <int>[0xff, 0xfe];
    for (final unit in input.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    bytes.add(0x41); // stray half of a code unit

    expect(
      () => parser.parse(
        Uint8List.fromList(bytes),
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
