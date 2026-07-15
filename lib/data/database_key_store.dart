import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/security/secret_protector.dart';

class DatabaseKeyException implements Exception {
  const DatabaseKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DatabaseKeyStore {
  DatabaseKeyStore({required SecretProtector protector})
    : _protector = protector;

  static const int keyLength = 32;
  static const int maxProtectedKeyBytes = 16 * 1024;

  final SecretProtector _protector;

  Future<void> delete(File keyFile) async {
    for (final candidate in [keyFile, File('${keyFile.path}.new')]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<Uint8List> loadOrCreate({
    required File keyFile,
    required bool databaseExists,
  }) async {
    if (await keyFile.exists()) {
      return _load(keyFile);
    }
    if (databaseExists) {
      throw const DatabaseKeyException(
        'The encrypted library key is missing. Reset is required; the old '
        'library cannot be recovered.',
      );
    }

    final random = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(keyLength, (_) => random.nextInt(256)),
    );
    final protectedKey = _protector.protect(key);
    final temporary = File('${keyFile.path}.new');
    try {
      await keyFile.parent.create(recursive: true);
      final sink = await temporary.open(mode: FileMode.writeOnly);
      try {
        await sink.writeFrom(protectedKey);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temporary.rename(keyFile.path);
      return key;
    } on Object {
      key.fillRange(0, key.length, 0);
      rethrow;
    } finally {
      protectedKey.fillRange(0, protectedKey.length, 0);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List> _load(File keyFile) async {
    final length = await keyFile.length();
    if (length <= 0 || length > maxProtectedKeyBytes) {
      throw const DatabaseKeyException('The encrypted library key is invalid.');
    }
    final protectedKey = await keyFile.readAsBytes();
    try {
      final key = _protector.unprotect(protectedKey);
      if (key.length != keyLength) {
        key.fillRange(0, key.length, 0);
        throw const DatabaseKeyException(
          'The encrypted library key is invalid.',
        );
      }
      return key;
    } finally {
      protectedKey.fillRange(0, protectedKey.length, 0);
    }
  }
}
