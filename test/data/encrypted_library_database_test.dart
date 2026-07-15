import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/encrypted_library_database.dart';
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
}

Uint8List _key() =>
    Uint8List.fromList(List<int>.generate(32, (index) => index));
