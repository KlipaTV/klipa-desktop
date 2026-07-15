import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/security/secret_protector.dart';
import 'package:klipa_player_windows/data/database_key_store.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'klipa-key-test-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test(
    'creates a protected 256-bit key and loads the same key later',
    () async {
      final keyFile = File('${temporaryDirectory.path}/library.key');
      final store = DatabaseKeyStore(protector: const _TestProtector());

      final created = await store.loadOrCreate(
        keyFile: keyFile,
        databaseExists: false,
      );
      final loaded = await store.loadOrCreate(
        keyFile: keyFile,
        databaseExists: false,
      );

      expect(created, hasLength(DatabaseKeyStore.keyLength));
      expect(loaded, created);
      expect(await keyFile.readAsBytes(), isNot(created));
    },
  );

  test('does not replace a missing key for an existing database', () async {
    final keyFile = File('${temporaryDirectory.path}/library.key');
    final store = DatabaseKeyStore(protector: const _TestProtector());

    await expectLater(
      store.loadOrCreate(keyFile: keyFile, databaseExists: true),
      throwsA(isA<DatabaseKeyException>()),
    );
    expect(await keyFile.exists(), isFalse);
  });
}

final class _TestProtector implements SecretProtector {
  const _TestProtector();

  @override
  Uint8List protect(Uint8List clearText) => _xor(clearText);

  @override
  Uint8List unprotect(Uint8List protectedData) => _xor(protectedData);

  Uint8List _xor(Uint8List value) => Uint8List.fromList(
    value.map((byte) => byte ^ 0xa5).toList(growable: false),
  );
}
