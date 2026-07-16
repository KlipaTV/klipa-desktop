import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'database_key_store.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStoragePlatform? storage})
    : _storage = storage ?? FlutterSecureStoragePlatform.instance;

  final FlutterSecureStoragePlatform _storage;

  @override
  Future<String?> read(String key) =>
      _storage.read(key: key, options: const {});

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value, options: const {});

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key, options: const {});
}

/// Stores only the random database key in the desktop Secret Service keyring.
/// Playlist, provider, channel, and EPG data remain in encrypted SQLite.
final class LinuxDatabaseKeyStore {
  LinuxDatabaseKeyStore({SecureValueStore? storage})
    : _storage = storage ?? FlutterSecureValueStore();

  static const _storageKey = 'tv.klipa.player.library-key.v1';

  final SecureValueStore _storage;

  Future<Uint8List> loadOrCreate({required bool databaseExists}) async {
    try {
      final encoded = await _storage.read(_storageKey);
      if (encoded != null) return _decode(encoded);
      if (databaseExists) {
        throw const DatabaseKeyException(
          'The encrypted library key is missing. Reset is required; the old '
          'library cannot be recovered.',
        );
      }
      final random = Random.secure();
      final key = Uint8List.fromList(
        List<int>.generate(
          DatabaseKeyStore.keyLength,
          (_) => random.nextInt(256),
        ),
      );
      await _storage.write(_storageKey, base64UrlEncode(key));
      return key;
    } on DatabaseKeyException {
      rethrow;
    } on Object {
      throw const DatabaseKeyException(
        'The Linux keyring is unavailable. Unlock the desktop keyring and retry.',
      );
    }
  }

  Future<void> delete() async {
    try {
      await _storage.delete(_storageKey);
    } on Object {
      throw const DatabaseKeyException(
        'The encrypted library key could not be removed from the Linux keyring.',
      );
    }
  }

  Uint8List _decode(String encoded) {
    try {
      final key = base64Url.decode(encoded);
      if (key.length != DatabaseKeyStore.keyLength) {
        key.fillRange(0, key.length, 0);
        throw const FormatException();
      }
      return key;
    } on FormatException {
      throw const DatabaseKeyException(
        'The encrypted library key is invalid. Reset is required.',
      );
    }
  }
}
