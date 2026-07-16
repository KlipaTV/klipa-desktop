import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/database_key_store.dart';
import 'package:klipa_player_windows/data/linux_database_key_store.dart';

void main() {
  test(
    'creates and restores a 256-bit key through the keyring boundary',
    () async {
      final values = <String, String>{};
      final store = LinuxDatabaseKeyStore(storage: _MemoryStore(values));

      final created = await store.loadOrCreate(databaseExists: false);
      final restored = await store.loadOrCreate(databaseExists: true);

      expect(created, hasLength(DatabaseKeyStore.keyLength));
      expect(restored, created);
      expect(values.values.single, isNot(contains(created.toString())));
      created.fillRange(0, created.length, 0);
      restored.fillRange(0, restored.length, 0);
    },
  );

  test('refuses to replace a missing key for an existing database', () async {
    final store = LinuxDatabaseKeyStore(storage: _MemoryStore({}));

    await expectLater(
      store.loadOrCreate(databaseExists: true),
      throwsA(isA<DatabaseKeyException>()),
    );
  });

  test('deletes the keyring entry during reset', () async {
    final values = <String, String>{};
    final store = LinuxDatabaseKeyStore(storage: _MemoryStore(values));
    final key = await store.loadOrCreate(databaseExists: false);
    key.fillRange(0, key.length, 0);

    await store.delete();

    expect(values, isEmpty);
  });
}

final class _MemoryStore implements SecureValueStore {
  _MemoryStore(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
