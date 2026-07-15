import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/encrypted_library_database.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'klipa-db-test-',
    );
    databasePath = '${temporaryDirectory.path}/library.db';
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test(
    'requires a key and does not expose a plaintext marker on disk',
    () async {
      const marker = 'KLIPA_SECRET_MARKER_d4f71c6f';
      final database = EncryptedLibraryDatabase.open(
        path: databasePath,
        key: _key(),
      );
      database.writeProbeForTest(marker);
      expect(database.readProbeForTest(), marker);
      database.close();

      final bytes = await File(databasePath).readAsBytes();
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(marker)));
      expect(bytes.take(16), isNot(utf8.encode('SQLite format 3\u0000')));

      final unkeyed = sqlite3.open(databasePath);
      try {
        expect(
          () => unkeyed.select('SELECT * FROM sqlite_master'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        unkeyed.close();
      }

      final reopened = EncryptedLibraryDatabase.open(
        path: databasePath,
        key: _key(),
      );
      expect(reopened.readProbeForTest(), marker);
      reopened.close();
    },
  );

  test('migrates a legacy metadata database transactionally', () {
    _createLegacyV1Database(databasePath, migrationStatus: 'in_progress:1:2');

    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );

    expect(
      database.currentSchemaVersion,
      EncryptedLibraryDatabase.schemaVersion,
    );
    expect(database.migrationStatus, 'clean');
    expect(database.loadSourceSummaries(), isEmpty);
    database.close();
  });

  test('rejects a database created by a newer schema', () {
    _createLegacyV1Database(databasePath, version: 999);

    expect(
      () => EncryptedLibraryDatabase.open(path: databasePath, key: _key()),
      throwsA(
        isA<LibraryMigrationException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(databasePath)),
        ),
      ),
    );
  });

  test('keeps secrets out of library summary queries', () {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    final source = _source(
      location: 'https://provider.invalid/list?token=source-secret',
    );
    database.replaceSourceSnapshot(
      source: source,
      username: 'private-user',
      password: 'private-password',
      channels: [
        _channel(
          name: 'News',
          stream: 'https://provider.invalid/live/private-stream',
          headers: const {'Referer': 'https://private-referrer.invalid'},
        ),
      ],
    );

    final sourceSummary = database.loadSourceSummaries().single;
    final channelSummary = database.loadChannelSummaries().single;
    expect(sourceSummary.secretReference, 'source:source-1');
    expect(channelSummary.secretReference, 'channel:source-1:channel-1');
    expect(channelSummary.name, 'News');

    final sourceSecret = database.readSourceSecret('source-1')!;
    expect(sourceSecret.location, source.location);
    expect(sourceSecret.username, 'private-user');
    expect(sourceSecret.password, 'private-password');
    final channelSecret = database.readChannelSecret(
      sourceId: 'source-1',
      channelId: 'channel-1',
    )!;
    expect(channelSecret.streamUri.toString(), contains('private-stream'));
    expect(channelSecret.httpHeaders['Referer'], contains('private-referrer'));
    database.close();
  });

  test('refresh is atomic and preserves stable favorites', () {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    final source = _source();
    database.replaceSourceSnapshot(
      source: source,
      channels: [
        _channel(name: 'Working snapshot', stream: 'https://old.invalid'),
      ],
    );
    database.setFavorite(
      sourceId: source.id,
      channelId: 'channel-1',
      favorite: true,
    );

    expect(
      () => database.replaceSourceSnapshot(
        source: source,
        channels: _interruptedRefresh(),
      ),
      throwsStateError,
    );
    var summary = database.loadChannelSummaries().single;
    expect(summary.name, 'Working snapshot');
    expect(summary.isFavorite, isTrue);
    expect(
      database
          .readChannelSecret(sourceId: source.id, channelId: 'channel-1')!
          .streamUri
          .host,
      'old.invalid',
    );

    database.replaceSourceSnapshot(
      source: source,
      channels: [
        _channel(name: 'Refreshed snapshot', stream: 'https://new.invalid'),
      ],
    );
    summary = database.loadChannelSummaries().single;
    expect(summary.name, 'Refreshed snapshot');
    expect(summary.isFavorite, isTrue);
    database.close();
  });

  test('stores a 10,000-channel snapshot through the bounded write path', () {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );

    database.replaceSourceSnapshot(
      source: _source(),
      channels: Iterable.generate(
        10000,
        (index) => Channel(
          id: 'channel-$index',
          name: 'Channel $index',
          streamUri: Uri.parse('https://stream.invalid/live/$index'),
          sourceId: 'source-1',
          allowsPrivateNetwork: false,
          group: 'Group ${index % 20}',
        ),
      ),
    );

    expect(
      database.loadChannelSummaries(sourceId: 'source-1'),
      hasLength(10000),
    );
    database.close();
  });

  test('rejects a twenty-first source without changing the library', () {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    for (var index = 0; index < EncryptedLibraryDatabase.maxSources; index++) {
      final source = PlaylistSource(
        id: 'source-$index',
        name: 'Source $index',
        kind: PlaylistSourceKind.remoteUrl,
        location: 'https://source-$index.invalid/list',
        allowsPrivateNetwork: false,
        importedAt: DateTime.utc(2026, 7, 15),
      );
      database.replaceSourceSnapshot(
        source: source,
        channels: [
          Channel(
            id: 'channel-$index',
            name: 'Channel $index',
            streamUri: Uri.parse('https://stream.invalid/$index'),
            sourceId: source.id,
            allowsPrivateNetwork: false,
          ),
        ],
      );
    }

    expect(
      () => database.replaceSourceSnapshot(
        source: PlaylistSource(
          id: 'source-over-limit',
          name: 'Over limit',
          kind: PlaylistSourceKind.remoteUrl,
          location: 'https://over-limit.invalid/list',
          allowsPrivateNetwork: false,
          importedAt: DateTime.utc(2026, 7, 15),
        ),
        channels: [
          Channel(
            id: 'over-limit',
            name: 'Over limit',
            streamUri: Uri.parse('https://stream.invalid/over-limit'),
            sourceId: 'source-over-limit',
            allowsPrivateNetwork: false,
          ),
        ],
      ),
      throwsA(isA<LibraryDatabaseException>()),
    );
    expect(database.loadSourceSummaries(), hasLength(20));
    database.close();
  });

  test('database, WAL and SHM do not expose seeded secrets', () async {
    const secrets = [
      'KLIPA_WAL_LOCATION_17c1',
      'KLIPA_WAL_USERNAME_22d2',
      'KLIPA_WAL_PASSWORD_39e3',
      'KLIPA_WAL_STREAM_44f4',
      'KLIPA_WAL_HEADER_58a5',
    ];
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    database.replaceSourceSnapshot(
      source: _source(location: 'https://example.invalid/${secrets[0]}'),
      username: secrets[1],
      password: secrets[2],
      channels: [
        _channel(
          name: 'Sensitive channel',
          stream: 'https://example.invalid/${secrets[3]}',
          headers: {'Origin': secrets[4]},
        ),
      ],
    );

    final files = [
      File(databasePath),
      File('$databasePath-wal'),
      File('$databasePath-shm'),
    ];
    for (final file in files) {
      expect(
        await file.exists(),
        isTrue,
        reason: '${file.path} was not created',
      );
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      for (final secret in secrets) {
        expect(
          text,
          isNot(contains(secret)),
          reason: '${file.path} leaked data',
        );
      }
    }
    database.close();
  });

  test('wrong keys fail with a path-free recovery error', () {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    database.writeProbeForTest('seed');
    database.close();

    expect(
      () => EncryptedLibraryDatabase.open(
        path: databasePath,
        key: Uint8List.fromList(List<int>.filled(32, 0xf1)),
      ),
      throwsA(
        isA<LibraryDatabaseException>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('Reset may be required'),
            isNot(contains(databasePath)),
          ),
        ),
      ),
    );
  });

  test('deletes the database and encrypted sidecars for reset', () async {
    final database = EncryptedLibraryDatabase.open(
      path: databasePath,
      key: _key(),
    );
    database.writeProbeForTest('seed');
    database.close();
    await File('$databasePath-wal').writeAsString('stale wal');
    await File('$databasePath-shm').writeAsString('stale shm');

    await EncryptedLibraryDatabase.deleteFiles(databasePath);

    expect(await File(databasePath).exists(), isFalse);
    expect(await File('$databasePath-wal').exists(), isFalse);
    expect(await File('$databasePath-shm').exists(), isFalse);
  });
}

Uint8List _key() =>
    Uint8List.fromList(List<int>.generate(32, (index) => index));

PlaylistSource _source({String location = 'https://provider.invalid/list'}) =>
    PlaylistSource(
      id: 'source-1',
      name: 'Provider',
      kind: PlaylistSourceKind.xtream,
      location: location,
      allowsPrivateNetwork: false,
      importedAt: DateTime.utc(2026, 7, 15),
    );

Channel _channel({
  required String name,
  required String stream,
  Map<String, String> headers = const {},
}) => Channel(
  id: 'channel-1',
  name: name,
  streamUri: Uri.parse(stream),
  sourceId: 'source-1',
  allowsPrivateNetwork: false,
  group: 'News',
  httpHeaders: headers,
);

Iterable<Channel> _interruptedRefresh() sync* {
  yield _channel(name: 'Partial update', stream: 'https://partial.invalid');
  throw StateError('Synthetic interrupted refresh');
}

void _createLegacyV1Database(
  String path, {
  int version = 1,
  String? migrationStatus,
}) {
  final database = sqlite3.open(path);
  final key = _key();
  final hexKey = key
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  try {
    database
      ..execute("PRAGMA key = '$hexKey'")
      ..execute('''
        CREATE TABLE app_metadata (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        ) WITHOUT ROWID
      ''')
      ..execute(
        "INSERT INTO app_metadata (key, value) VALUES ('schema_version', ?)",
        [version.toString()],
      );
    if (migrationStatus != null) {
      database.execute(
        "INSERT INTO app_metadata (key, value) VALUES ('migration_status', ?)",
        [migrationStatus],
      );
    }
  } finally {
    key.fillRange(0, key.length, 0);
    database.close();
  }
}
