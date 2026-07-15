import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../core/security/dpapi_secret_protector.dart';
import '../core/security/secret_protector.dart';
import '../domain/channel.dart';
import '../domain/playlist_source.dart';
import 'database_key_store.dart';
import 'encrypted_library_database.dart';

class LibrarySnapshot {
  const LibrarySnapshot({required this.sources, required this.channels});

  const LibrarySnapshot.empty() : sources = const [], channels = const [];

  final List<PlaylistSource> sources;
  final List<Channel> channels;
}

abstract interface class LibraryStore {
  Future<LibrarySnapshot> load();

  Future<void> replaceSourceSnapshot({
    required PlaylistSource source,
    required List<Channel> channels,
    String? username,
    String? password,
  });

  Future<void> reset();
}

/// Keeps non-Windows development and widget tests independent of DPAPI.
/// Production builds target Windows and use [EncryptedLibraryStore].
final class DisabledLibraryStore implements LibraryStore {
  const DisabledLibraryStore();

  @override
  Future<LibrarySnapshot> load() async => const LibrarySnapshot.empty();

  @override
  Future<void> replaceSourceSnapshot({
    required PlaylistSource source,
    required List<Channel> channels,
    String? username,
    String? password,
  }) async {}

  @override
  Future<void> reset() async {}
}

final class EncryptedLibraryStore implements LibraryStore {
  EncryptedLibraryStore({
    Future<Directory> Function()? rootDirectory,
    SecretProtector protector = const DpapiSecretProtector(),
  }) : _rootDirectory = rootDirectory ?? getApplicationCacheDirectory,
       _protector = protector;

  final Future<Directory> Function() _rootDirectory;
  final SecretProtector _protector;

  @override
  Future<LibrarySnapshot> load() async {
    final paths = await _paths();
    if (!await File(paths.databasePath).exists() &&
        !await File(paths.keyPath).exists()) {
      return const LibrarySnapshot.empty();
    }
    final protector = _protector;
    return Isolate.run(() => _loadEncryptedLibrary(paths, protector));
  }

  @override
  Future<void> replaceSourceSnapshot({
    required PlaylistSource source,
    required List<Channel> channels,
    String? username,
    String? password,
  }) async {
    final paths = await _paths();
    final protector = _protector;
    await Isolate.run(
      () => _replaceEncryptedSource(
        paths,
        protector,
        source,
        channels,
        username,
        password,
      ),
    );
  }

  @override
  Future<void> reset() async {
    final paths = await _paths();
    await Isolate.run(() => _resetEncryptedLibrary(paths));
  }

  Future<_LibraryPaths> _paths() async {
    final root = await _rootDirectory();
    final separator = Platform.pathSeparator;
    return _LibraryPaths(
      databasePath: '${root.path}${separator}library.db',
      keyPath: '${root.path}${separator}library.key',
    );
  }
}

class _LibraryPaths {
  const _LibraryPaths({required this.databasePath, required this.keyPath});

  final String databasePath;
  final String keyPath;
}

Future<EncryptedLibraryDatabase> _openEncryptedLibrary(
  _LibraryPaths paths,
  SecretProtector protector,
) async {
  final databaseFile = File(paths.databasePath);
  final key = await DatabaseKeyStore(protector: protector).loadOrCreate(
    keyFile: File(paths.keyPath),
    databaseExists: await databaseFile.exists(),
  );
  try {
    return EncryptedLibraryDatabase.open(path: databaseFile.path, key: key);
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

Future<LibrarySnapshot> _loadEncryptedLibrary(
  _LibraryPaths paths,
  SecretProtector protector,
) async {
  EncryptedLibraryDatabase? database;
  try {
    database = await _openEncryptedLibrary(paths, protector);
    return LibrarySnapshot(
      sources: List.unmodifiable(database.loadSources()),
      channels: List.unmodifiable(database.loadChannels()),
    );
  } on DatabaseKeyException {
    rethrow;
  } on LibraryDatabaseException {
    rethrow;
  } on Object {
    throw const LibraryDatabaseException(
      'The encrypted library could not be read. Reset may be required.',
    );
  } finally {
    database?.close();
  }
}

Future<void> _replaceEncryptedSource(
  _LibraryPaths paths,
  SecretProtector protector,
  PlaylistSource source,
  List<Channel> channels,
  String? username,
  String? password,
) async {
  EncryptedLibraryDatabase? database;
  try {
    database = await _openEncryptedLibrary(paths, protector);
    database.replaceSourceSnapshot(
      source: source,
      channels: channels,
      username: username,
      password: password,
    );
  } finally {
    database?.close();
  }
}

Future<void> _resetEncryptedLibrary(_LibraryPaths paths) async {
  await EncryptedLibraryDatabase.deleteFiles(paths.databasePath);
  await DatabaseKeyStore(
    protector: const DpapiSecretProtector(),
  ).delete(File(paths.keyPath));
}
