import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

class EncryptedLibraryDatabase {
  EncryptedLibraryDatabase._(this._database);

  final Database _database;

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
        throw StateError(
          'The loaded SQLite library does not support encryption.',
        );
      }

      database
        ..execute('PRAGMA foreign_keys = ON')
        ..execute('PRAGMA trusted_schema = OFF')
        ..execute('PRAGMA secure_delete = ON')
        ..execute('PRAGMA synchronous = FULL')
        ..execute('PRAGMA journal_mode = WAL')
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
      database.select('SELECT value FROM app_metadata WHERE key = ?', [
        'schema_version',
      ]);
      return EncryptedLibraryDatabase._(database);
    } on Object {
      database.close();
      rethrow;
    } finally {
      key.fillRange(0, key.length, 0);
    }
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
