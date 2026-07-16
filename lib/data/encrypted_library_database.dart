import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../core/security/network_policy.dart';
import '../domain/channel.dart';
import '../domain/channel_identity.dart';
import '../domain/playlist_source.dart';

class LibraryDatabaseException implements Exception {
  const LibraryDatabaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LibraryMigrationException extends LibraryDatabaseException {
  const LibraryMigrationException(super.message);
}

class LibrarySourceSummary {
  const LibrarySourceSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.allowsPrivateNetwork,
    required this.importedAt,
    required this.refreshedAt,
    required this.secretReference,
  });

  final String id;
  final String name;
  final PlaylistSourceKind kind;
  final bool allowsPrivateNetwork;
  final DateTime importedAt;
  final DateTime refreshedAt;
  final String secretReference;
}

class LibraryChannelSummary {
  const LibraryChannelSummary({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.group,
    required this.secretReference,
    required this.isFavorite,
  });

  final String id;
  final String sourceId;
  final String name;
  final String? group;
  final String secretReference;
  final bool isFavorite;
}

class StoredSourceSecret {
  const StoredSourceSecret({
    required this.location,
    required this.username,
    required this.password,
  });

  final String location;
  final String? username;
  final String? password;
}

class StoredChannelSecret {
  const StoredChannelSecret({
    required this.streamUri,
    required this.logoUri,
    required this.httpHeaders,
  });

  final Uri streamUri;
  final Uri? logoUri;
  final Map<String, String> httpHeaders;
}

class EncryptedLibraryDatabase {
  EncryptedLibraryDatabase._(this._database);

  static const int schemaVersion = 2;
  static const int maxSources = 20;
  static const int maxChannelsPerSource = 100000;

  final Database _database;

  static Future<void> deleteFiles(String path) async {
    for (final candidate in [path, '$path-wal', '$path-shm']) {
      final file = File(candidate);
      if (await file.exists()) await file.delete();
    }
  }

  static EncryptedLibraryDatabase open({
    required String path,
    required Uint8List key,
  }) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'Expected a 256-bit key.');
    }

    final database = sqlite3.open(path);
    try {
      final hexKey = key
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      database.execute("PRAGMA key = '$hexKey'");
      final cipher = database.select('PRAGMA cipher');
      if (cipher.isEmpty) {
        throw const LibraryDatabaseException(
          'The loaded SQLite library does not support encryption.',
        );
      }

      database
        ..execute('PRAGMA foreign_keys = ON')
        ..execute('PRAGMA trusted_schema = OFF')
        ..execute('PRAGMA secure_delete = ON')
        ..execute('PRAGMA synchronous = FULL')
        ..execute('PRAGMA journal_mode = WAL');
      _migrate(database);
      database.select('SELECT count(*) FROM app_metadata');
      return EncryptedLibraryDatabase._(database);
    } on LibraryDatabaseException {
      database.close();
      rethrow;
    } on Object {
      database.close();
      throw const LibraryDatabaseException(
        'The encrypted library could not be opened. Reset may be required.',
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static void _migrate(Database database) {
    database
      ..execute('''
        CREATE TABLE IF NOT EXISTS app_metadata (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        ) WITHOUT ROWID
      ''')
      ..execute('''
        INSERT OR IGNORE INTO app_metadata (key, value)
        VALUES ('schema_version', '1')
      ''');

    final versionValue = database
        .select("SELECT value FROM app_metadata WHERE key = 'schema_version'")
        .single['value'];
    final version = int.tryParse(versionValue as String);
    if (version == null || version < 1) {
      throw const LibraryMigrationException(
        'The encrypted library schema metadata is invalid.',
      );
    }
    if (version > schemaVersion) {
      throw const LibraryMigrationException(
        'This library was created by a newer version of Klipa Player.',
      );
    }

    var current = version;
    while (current < schemaVersion) {
      final next = current + 1;
      database.execute('BEGIN IMMEDIATE');
      try {
        database.execute(
          '''
          INSERT INTO app_metadata (key, value) VALUES ('migration_status', ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          ''',
          ['in_progress:$current:$next'],
        );
        switch (current) {
          case 1:
            _migrateV1ToV2(database);
          default:
            throw LibraryMigrationException(
              'No migration exists from schema version $current.',
            );
        }
        database
          ..execute(
            "UPDATE app_metadata SET value = ? WHERE key = 'schema_version'",
            [next.toString()],
          )
          ..execute(
            "UPDATE app_metadata SET value = 'clean' "
            "WHERE key = 'migration_status'",
          )
          ..execute('COMMIT');
        current = next;
      } on Object {
        database.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  static void _migrateV1ToV2(Database database) {
    database
      ..execute('''
        CREATE TABLE playlist_sources (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          kind TEXT NOT NULL,
          allows_private_network INTEGER NOT NULL CHECK (
            allows_private_network IN (0, 1)
          ),
          imported_at TEXT NOT NULL,
          refreshed_at TEXT NOT NULL
        ) WITHOUT ROWID
      ''')
      ..execute('''
        CREATE TABLE source_secrets (
          source_id TEXT PRIMARY KEY NOT NULL,
          location TEXT NOT NULL,
          username TEXT,
          password TEXT,
          FOREIGN KEY (source_id) REFERENCES playlist_sources(id)
            ON DELETE CASCADE
        ) WITHOUT ROWID
      ''')
      ..execute('''
        CREATE TABLE channels (
          source_id TEXT NOT NULL,
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          group_name TEXT,
          PRIMARY KEY (source_id, id),
          FOREIGN KEY (source_id) REFERENCES playlist_sources(id)
            ON DELETE CASCADE
        ) WITHOUT ROWID
      ''')
      ..execute('''
        CREATE INDEX channels_source_name
        ON channels(source_id, name COLLATE NOCASE)
      ''')
      ..execute('''
        CREATE TABLE channel_secrets (
          source_id TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          stream_uri TEXT NOT NULL,
          logo_uri TEXT,
          http_headers_json TEXT NOT NULL,
          PRIMARY KEY (source_id, channel_id),
          FOREIGN KEY (source_id, channel_id) REFERENCES channels(source_id, id)
            ON DELETE CASCADE
        ) WITHOUT ROWID
      ''')
      ..execute('''
        CREATE TABLE favorites (
          source_id TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (source_id, channel_id),
          FOREIGN KEY (source_id, channel_id) REFERENCES channels(source_id, id)
            ON DELETE CASCADE
        ) WITHOUT ROWID
      ''')
      ..execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        ) WITHOUT ROWID
      ''');
  }

  int get currentSchemaVersion => int.parse(
    _database
            .select(
              "SELECT value FROM app_metadata WHERE key = 'schema_version'",
            )
            .single['value']
        as String,
  );

  String get migrationStatus =>
      _database
              .select(
                "SELECT value FROM app_metadata "
                "WHERE key = 'migration_status'",
              )
              .firstOrNull?['value']
          as String? ??
      'clean';

  void replaceSourceSnapshot({
    required PlaylistSource source,
    required Iterable<Channel> channels,
    String? username,
    String? password,
  }) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final sourceExists = _database.select(
        'SELECT 1 FROM playlist_sources WHERE id = ?',
        [source.id],
      ).isNotEmpty;
      final sourceCount =
          _database
                  .select('SELECT count(*) AS count FROM playlist_sources')
                  .single['count']
              as int;
      if (!sourceExists && sourceCount >= maxSources) {
        throw const LibraryDatabaseException(
          'The library supports up to 20 sources.',
        );
      }
      final refreshedAt = DateTime.now().toUtc().toIso8601String();
      _database
        ..execute(
          '''
          INSERT INTO playlist_sources (
            id, name, kind, allows_private_network, imported_at, refreshed_at
          ) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            kind = excluded.kind,
            allows_private_network = excluded.allows_private_network,
            refreshed_at = excluded.refreshed_at
          ''',
          [
            source.id,
            source.name,
            source.kind.name,
            source.allowsPrivateNetwork ? 1 : 0,
            source.importedAt.toUtc().toIso8601String(),
            refreshedAt,
          ],
        )
        ..execute(
          '''
          INSERT INTO source_secrets (source_id, location, username, password)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(source_id) DO UPDATE SET
            location = excluded.location,
            username = excluded.username,
            password = excluded.password
          ''',
          [source.id, source.location, username, password],
        )
        ..execute('''
          CREATE TEMP TABLE IF NOT EXISTS refresh_channel_ids (
            channel_id TEXT PRIMARY KEY NOT NULL
          ) WITHOUT ROWID
        ''')
        ..execute('DELETE FROM refresh_channel_ids');

      final stageId = _database.prepare(
        'INSERT INTO refresh_channel_ids (channel_id) VALUES (?) '
        'ON CONFLICT(channel_id) DO NOTHING',
      );
      final upsertChannel = _database.prepare('''
        INSERT INTO channels (source_id, id, name, group_name)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(source_id, id) DO UPDATE SET
          name = excluded.name,
          group_name = excluded.group_name
      ''');
      final upsertSecret = _database.prepare('''
        INSERT INTO channel_secrets (
          source_id, channel_id, stream_uri, logo_uri, http_headers_json
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(source_id, channel_id) DO UPDATE SET
          stream_uri = excluded.stream_uri,
          logo_uri = excluded.logo_uri,
          http_headers_json = excluded.http_headers_json
      ''');
      try {
        var count = 0;
        for (final channel in channels) {
          count++;
          if (count > maxChannelsPerSource) {
            throw const LibraryDatabaseException(
              'The channel snapshot exceeds the 100,000 entry limit.',
            );
          }
          if (channel.sourceId != source.id) {
            throw ArgumentError(
              'A channel snapshot cannot contain a different source ID.',
            );
          }
          stageId.execute([channel.id]);
          upsertChannel.execute([
            source.id,
            channel.id,
            channel.name,
            channel.group,
          ]);
          upsertSecret.execute([
            source.id,
            channel.id,
            channel.streamUri.toString(),
            channel.logoUri?.toString(),
            jsonEncode(channel.httpHeaders),
          ]);
        }
      } finally {
        stageId.close();
        upsertChannel.close();
        upsertSecret.close();
      }

      _database
        ..execute(
          '''
          DELETE FROM channels
          WHERE source_id = ?
            AND id NOT IN (SELECT channel_id FROM refresh_channel_ids)
          ''',
          [source.id],
        )
        ..execute('DELETE FROM refresh_channel_ids')
        ..execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  List<LibrarySourceSummary> loadSourceSummaries() => _database
      .select('''
        SELECT id, name, kind, allows_private_network, imported_at, refreshed_at
        FROM playlist_sources
        ORDER BY name COLLATE NOCASE, id
      ''')
      .map(
        (row) => LibrarySourceSummary(
          id: row['id'] as String,
          name: row['name'] as String,
          kind: PlaylistSourceKind.values.byName(row['kind'] as String),
          allowsPrivateNetwork: row['allows_private_network'] == 1,
          importedAt: DateTime.parse(row['imported_at'] as String),
          refreshedAt: DateTime.parse(row['refreshed_at'] as String),
          secretReference: 'source:${row['id']}',
        ),
      )
      .toList(growable: false);

  List<LibraryChannelSummary> loadChannelSummaries({String? sourceId}) {
    final where = sourceId == null ? '' : 'WHERE c.source_id = ?';
    return _database
        .select('''
          SELECT c.source_id, c.id, c.name, c.group_name,
            CASE WHEN f.channel_id IS NULL THEN 0 ELSE 1 END AS is_favorite
          FROM channels c
          LEFT JOIN favorites f
            ON f.source_id = c.source_id AND f.channel_id = c.id
          $where
          ORDER BY c.name COLLATE NOCASE, c.id
          ''', sourceId == null ? const [] : [sourceId])
        .map(
          (row) => LibraryChannelSummary(
            id: row['id'] as String,
            sourceId: row['source_id'] as String,
            name: row['name'] as String,
            group: row['group_name'] as String?,
            secretReference: 'channel:${row['source_id']}:${row['id']}',
            isFavorite: row['is_favorite'] == 1,
          ),
        )
        .toList(growable: false);
  }

  List<Channel> loadChannels() => _database
      .select('''
        SELECT c.source_id, c.id, c.name, c.group_name,
          s.allows_private_network, x.stream_uri, x.logo_uri,
          x.http_headers_json
        FROM channels c
        INNER JOIN playlist_sources s ON s.id = c.source_id
        INNER JOIN channel_secrets x
          ON x.source_id = c.source_id AND x.channel_id = c.id
        ORDER BY c.name COLLATE NOCASE, c.id
      ''')
      .map(_channelFromRow)
      .toList(growable: false);

  Set<ChannelIdentity> loadFavoriteChannels() => {
    for (final row in _database.select('''
      SELECT source_id, channel_id
      FROM favorites
      ORDER BY source_id, channel_id
    '''))
      (
        sourceId: row['source_id'] as String,
        channelId: row['channel_id'] as String,
      ),
  };

  Channel _channelFromRow(Row row) {
    final streamUri = Uri.parse(row['stream_uri'] as String);
    const NetworkPolicy().validateHttpUriShape(streamUri);
    final logoUri = switch (row['logo_uri']) {
      final String value => Uri.parse(value),
      _ => null,
    };
    if (logoUri != null) const NetworkPolicy().validateHttpUriShape(logoUri);

    final decodedHeaders = jsonDecode(row['http_headers_json'] as String);
    if (decodedHeaders is! Map) {
      throw const LibraryDatabaseException(
        'The encrypted library contains invalid channel data.',
      );
    }
    final headers = <String, String>{};
    const allowedHeaders = {'User-Agent', 'Referer', 'Origin'};
    for (final entry in decodedHeaders.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          !allowedHeaders.contains(entry.key) ||
          (entry.value as String).length > 8192 ||
          (entry.value as String).contains('\r') ||
          (entry.value as String).contains('\n')) {
        throw const LibraryDatabaseException(
          'The encrypted library contains invalid channel data.',
        );
      }
      headers[entry.key as String] = entry.value as String;
    }
    return Channel(
      id: row['id'] as String,
      name: row['name'] as String,
      streamUri: streamUri,
      sourceId: row['source_id'] as String,
      allowsPrivateNetwork: row['allows_private_network'] == 1,
      group: row['group_name'] as String?,
      logoUri: logoUri,
      httpHeaders: headers,
    );
  }

  StoredSourceSecret? readSourceSecret(String sourceId) {
    final row = _database
        .select(
          '''
          SELECT location, username, password
          FROM source_secrets WHERE source_id = ?
          ''',
          [sourceId],
        )
        .firstOrNull;
    if (row == null) return null;
    return StoredSourceSecret(
      location: row['location'] as String,
      username: row['username'] as String?,
      password: row['password'] as String?,
    );
  }

  StoredChannelSecret? readChannelSecret({
    required String sourceId,
    required String channelId,
  }) {
    final row = _database
        .select(
          '''
          SELECT stream_uri, logo_uri, http_headers_json
          FROM channel_secrets WHERE source_id = ? AND channel_id = ?
          ''',
          [sourceId, channelId],
        )
        .firstOrNull;
    if (row == null) return null;
    final headers = (jsonDecode(row['http_headers_json'] as String) as Map)
        .cast<String, String>();
    return StoredChannelSecret(
      streamUri: Uri.parse(row['stream_uri'] as String),
      logoUri: switch (row['logo_uri']) {
        final String value => Uri.parse(value),
        _ => null,
      },
      httpHeaders: Map.unmodifiable(headers),
    );
  }

  void setFavorite({
    required String sourceId,
    required String channelId,
    required bool favorite,
  }) {
    if (favorite) {
      _database.execute(
        '''
        INSERT OR IGNORE INTO favorites (source_id, channel_id, created_at)
        VALUES (?, ?, ?)
        ''',
        [sourceId, channelId, DateTime.now().toUtc().toIso8601String()],
      );
    } else {
      _database.execute(
        'DELETE FROM favorites WHERE source_id = ? AND channel_id = ?',
        [sourceId, channelId],
      );
    }
  }

  void renameSource({required String sourceId, required String name}) {
    final normalized = name.trim();
    if (normalized.isEmpty ||
        normalized.length > 120 ||
        normalized.contains('\r') ||
        normalized.contains('\n')) {
      throw const LibraryDatabaseException('Enter a valid source name.');
    }
    _database.execute('UPDATE playlist_sources SET name = ? WHERE id = ?', [
      normalized,
      sourceId,
    ]);
    if (_database.updatedRows == 0) {
      throw const LibraryDatabaseException('The source no longer exists.');
    }
  }

  void deleteSource(String sourceId) {
    _database.execute('DELETE FROM playlist_sources WHERE id = ?', [sourceId]);
  }

  void writeProbeForTest(String value) {
    _database.execute(
      '''
      INSERT INTO app_metadata (key, value) VALUES ('test_probe', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [value],
    );
  }

  String? readProbeForTest() =>
      _database
              .select("SELECT value FROM app_metadata WHERE key = 'test_probe'")
              .firstOrNull?['value']
          as String?;

  void close() => _database.close();
}
