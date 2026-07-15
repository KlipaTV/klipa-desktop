import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../core/security/dpapi_secret_protector.dart';
import '../core/security/secret_protector.dart';
import '../domain/channel.dart';
import '../domain/library_source.dart';
import '../domain/playlist_source.dart';
import 'database_key_store.dart';
import 'encrypted_library_database.dart';

class LibrarySnapshot {
  const LibrarySnapshot({required this.sources, required this.channels});

  const LibrarySnapshot.empty() : sources = const [], channels = const [];

  final List<LibrarySource> sources;
  final List<Channel> channels;
}

class SourceRefreshAccess {
  const SourceRefreshAccess({
    required this.source,
    required this.username,
    required this.password,
  });

  final PlaylistSource source;
  final String? username;
  final String? password;
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

  Future<SourceRefreshAccess?> readSourceRefreshAccess(String sourceId);

  Future<void> renameSource({required String sourceId, required String name});

  Future<void> deleteSource(String sourceId);
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

  @override
  Future<SourceRefreshAccess?> readSourceRefreshAccess(String sourceId) async =>
      null;

  @override
  Future<void> renameSource({
    required String sourceId,
    required String name,
  }) async {}

  @override
  Future<void> deleteSource(String sourceId) async {}
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

  @override
  Future<SourceRefreshAccess?> readSourceRefreshAccess(String sourceId) async {
    final paths = await _paths();
    final protector = _protector;
    return Isolate.run(
      () => _readSourceRefreshAccess(paths, protector, sourceId),
    );
  }

  @override
  Future<void> renameSource({
    required String sourceId,
    required String name,
  }) async {
    final paths = await _paths();
    final protector = _protector;
    await Isolate.run(
      () => _renameEncryptedSource(paths, protector, sourceId, name),
    );
  }

  @override
  Future<void> deleteSource(String sourceId) async {
    final paths = await _paths();
    final protector = _protector;
    await Isolate.run(() => _deleteEncryptedSource(paths, protector, sourceId));
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
    final sourceSummaries = database.loadSourceSummaries();
    return LibrarySnapshot(
      sources: List.unmodifiable(
        sourceSummaries.map(
          (source) => LibrarySource(
            id: source.id,
            name: source.name,
            kind: source.kind,
            allowsPrivateNetwork: source.allowsPrivateNetwork,
            importedAt: source.importedAt,
            refreshedAt: source.refreshedAt,
          ),
        ),
      ),
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

Future<SourceRefreshAccess?> _readSourceRefreshAccess(
  _LibraryPaths paths,
  SecretProtector protector,
  String sourceId,
) async {
  EncryptedLibraryDatabase? database;
  try {
    database = await _openEncryptedLibrary(paths, protector);
    final summaries = database.loadSourceSummaries();
    LibrarySourceSummary? summary;
    for (final candidate in summaries) {
      if (candidate.id == sourceId) {
        summary = candidate;
        break;
      }
    }
    final secret = database.readSourceSecret(sourceId);
    if (summary == null || secret == null) return null;
    return SourceRefreshAccess(
      source: PlaylistSource(
        id: summary.id,
        name: summary.name,
        kind: summary.kind,
        location: secret.location,
        allowsPrivateNetwork: summary.allowsPrivateNetwork,
        importedAt: summary.importedAt,
      ),
      username: secret.username,
      password: secret.password,
    );
  } finally {
    database?.close();
  }
}

Future<void> _renameEncryptedSource(
  _LibraryPaths paths,
  SecretProtector protector,
  String sourceId,
  String name,
) async {
  EncryptedLibraryDatabase? database;
  try {
    database = await _openEncryptedLibrary(paths, protector);
    database.renameSource(sourceId: sourceId, name: name);
  } finally {
    database?.close();
  }
}

Future<void> _deleteEncryptedSource(
  _LibraryPaths paths,
  SecretProtector protector,
  String sourceId,
) async {
  EncryptedLibraryDatabase? database;
  try {
    database = await _openEncryptedLibrary(paths, protector);
    database.deleteSource(sourceId);
  } finally {
    database?.close();
  }
}
