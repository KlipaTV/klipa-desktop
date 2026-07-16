import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:klipa_player_windows/core/network/bounded_http_client.dart';
import 'package:klipa_player_windows/data/m3u_parser.dart';
import 'package:klipa_player_windows/data/xmltv_parser.dart';
import 'package:klipa_player_windows/data/xtream_client.dart';

const _m3uSeed = '''#EXTM3U
#EXTINF:-1 tvg-id="one" group-title="News",Channel One
https://stream.example/live/one.ts
''';
const _xmlSeed = '''<?xml version="1.0" encoding="UTF-8"?>
<tv><programme channel="one" start="20260716090000 +0000" stop="20260716100000 +0000"><title>News</title><desc>Fixture</desc></programme></tv>
''';

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 20000 : int.parse(arguments.single);
  if (iterations < 1 || iterations > 1000000) {
    throw ArgumentError.value(iterations, 'iterations', 'must be 1..1000000');
  }

  final random = Random(0x4b4c4950);
  final m3u = const M3uParser();
  final xmltv = const XmltvParser(
    compressedByteLimit: 64 * 1024,
    decompressedByteLimit: 64 * 1024,
    programmeLimit: 100,
  );
  final now = DateTime.utc(2026, 7, 16, 9, 30);
  final m3uBytes = Uint8List.fromList(_m3uSeed.codeUnits);
  final xmlBytes = Uint8List.fromList(_xmlSeed.codeUnits);

  for (var index = 0; index < iterations; index++) {
    final bytes = switch (index % 3) {
      0 => _mutate(m3uBytes, random),
      1 => _mutate(xmlBytes, random),
      _ => _randomBytes(random),
    };

    try {
      final result = m3u.parse(
        bytes,
        sourceId: 'fuzz-source',
        allowPrivateNetwork: false,
      );
      if (result.channels.length > M3uParser.maxChannels) {
        throw StateError('M3U parser exceeded its channel bound.');
      }
    } on PlaylistFormatException {
      // Rejection is the expected result for most mutated inputs.
    }

    try {
      final result = xmltv.parse(bytes, sourceId: 'fuzz-source', nowUtc: now);
      if (result.programmes.length > 100) {
        throw StateError('XMLTV parser exceeded its programme bound.');
      }
    } on XmltvFormatException {
      // Rejection is the expected result for most mutated inputs.
    }
  }

  final xtreamIterations = min(iterations, 1000);
  for (var index = 0; index < xtreamIterations; index++) {
    final http = _FuzzHttpClient([
      {
        'user_info': {'auth': 1, 'status': 'Active'},
      },
      _randomJson(random, 0),
      _randomJson(random, 0),
    ]);
    try {
      final result = await XtreamClient(httpClient: http).loadLiveChannels(
        server: Uri.parse('https://provider.example'),
        username: 'fuzz-user',
        password: 'fuzz-password',
        allowPrivateNetwork: false,
      );
      if (result.channels.length > XtreamClient.maxChannels) {
        throw StateError('Xtream parser exceeded its channel bound.');
      }
    } on XtreamException {
      // Random catalog shapes are expected to be rejected safely.
    }
  }

  stdout.writeln(
    'Release parser fuzz passed: $iterations M3U/XMLTV and '
    '$xtreamIterations Xtream inputs.',
  );
}

Object? _randomJson(Random random, int depth) {
  if (depth >= 4) {
    return switch (random.nextInt(4)) {
      0 => null,
      1 => random.nextBool(),
      2 => random.nextInt(1 << 31),
      _ => _randomText(random),
    };
  }
  return switch (random.nextInt(6)) {
    0 => null,
    1 => random.nextBool(),
    2 => random.nextInt(1 << 31),
    3 => _randomText(random),
    4 => List<Object?>.generate(
      random.nextInt(12),
      (_) => _randomJson(random, depth + 1),
    ),
    _ => <String, Object?>{
      for (var index = 0; index < random.nextInt(12); index++)
        _randomText(random): _randomJson(random, depth + 1),
    },
  };
}

String _randomText(Random random) => String.fromCharCodes(
  List<int>.generate(
    random.nextInt(256),
    (_) => 0x20 + random.nextInt(0x7f - 0x20),
  ),
);

final class _FuzzHttpClient extends BoundedHttpClient {
  _FuzzHttpClient(List<Object?> responses)
    : _responses = responses
          .map((value) => Uint8List.fromList(utf8.encode(jsonEncode(value))))
          .toList();

  final List<Uint8List> _responses;

  @override
  Future<Uint8List> getPlaylist(
    Uri initialUri, {
    required bool allowPrivateNetwork,
  }) async => _responses.removeAt(0);
}

Uint8List _randomBytes(Random random) {
  final length = random.nextInt(16 * 1024);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256), growable: false),
  );
}

Uint8List _mutate(Uint8List seed, Random random) {
  final bytes = seed.toList(growable: true);
  final mutations = 1 + random.nextInt(16);
  for (var mutation = 0; mutation < mutations; mutation++) {
    switch (random.nextInt(4)) {
      case 0:
        if (bytes.isNotEmpty) {
          bytes[random.nextInt(bytes.length)] = random.nextInt(256);
        }
      case 1:
        if (bytes.isNotEmpty) bytes.removeAt(random.nextInt(bytes.length));
      case 2:
        if (bytes.length < 64 * 1024) {
          bytes.insert(random.nextInt(bytes.length + 1), random.nextInt(256));
        }
      case 3:
        if (bytes.isNotEmpty && bytes.length < 64 * 1024) {
          final start = random.nextInt(bytes.length);
          final length = min(random.nextInt(64), bytes.length - start);
          bytes.insertAll(
            random.nextInt(bytes.length + 1),
            bytes.sublist(start, start + length),
          );
        }
    }
  }
  return Uint8List.fromList(bytes);
}
