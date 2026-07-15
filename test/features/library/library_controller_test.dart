import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/data/playlist_import_service.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/library_source.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
import 'package:klipa_player_windows/features/library/library_controller.dart';

void main() {
  test(
    'restores the encrypted library without autoplaying a channel',
    () async {
      final store = _FakeLibraryStore(
        initial: LibrarySnapshot(
          sources: [_librarySource()],
          channels: [_channel('saved')],
        ),
      );
      final container = _container(store: store);
      addTearDown(container.dispose);

      await _waitForLoad(container);
      final state = container.read(libraryControllerProvider);

      expect(state.sources.single.id, 'source-1');
      expect(state.channels.single.id, 'saved');
      expect(state.selectedChannel, isNull);
      expect(state.isLoading, isFalse);
    },
  );

  test('persists an Xtream import before publishing it to state', () async {
    final saveGate = Completer<void>();
    final result = PlaylistImportResult(
      source: _source(),
      channels: [_channel('new')],
      warnings: const [],
    );
    final store = _FakeLibraryStore(saveGate: saveGate);
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(result: result),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    final import = container
        .read(libraryControllerProvider.notifier)
        .importXtream(
          server: 'https://provider.invalid',
          username: 'test-user',
          password: 'test-password',
          allowPrivateNetwork: false,
        );
    await _waitUntil(() => store.saveStarted);

    expect(container.read(libraryControllerProvider).channels, isEmpty);
    expect(container.read(libraryControllerProvider).isImporting, isTrue);
    saveGate.complete();
    await import;

    expect(store.savedSource?.id, 'source-1');
    expect(store.savedUsername, 'test-user');
    expect(store.savedPassword, 'test-password');
    expect(container.read(libraryControllerProvider).channels.single.id, 'new');
  });

  test('a failed save preserves the previous working library', () async {
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [_channel('working')],
      ),
      saveError: Exception(
        'failed https://user:password@example.invalid/private?token=secret',
      ),
    );
    final result = PlaylistImportResult(
      source: _source(),
      channels: [_channel('replacement')],
      warnings: const [],
    );
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(result: result),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .importUrl(
          'https://provider.invalid/list.m3u',
          allowPrivateNetwork: false,
        );
    final state = container.read(libraryControllerProvider);

    expect(state.channels.single.id, 'working');
    expect(state.error, isNotNull);
    expect(state.error, isNot(contains('password')));
    expect(state.error, isNot(contains('secret')));
  });

  test(
    'a startup storage failure offers recovery and reset clears it',
    () async {
      final store = _FakeLibraryStore(
        loadError: Exception('The encrypted library key is missing.'),
      );
      final container = _container(store: store);
      addTearDown(container.dispose);

      await _waitForLoad(container);
      expect(
        container.read(libraryControllerProvider).recoveryRequired,
        isTrue,
      );

      await container.read(libraryControllerProvider.notifier).resetLibrary();

      final state = container.read(libraryControllerProvider);
      expect(store.resetCount, 1);
      expect(state.recoveryRequired, isFalse);
      expect(state.channels, isEmpty);
      expect(state.message, 'App data was reset.');
    },
  );

  test('refresh is atomic and preserves a stable selected channel', () async {
    final source = _source();
    final oldChannel = _channel('stable');
    final refreshedChannel = Channel(
      id: oldChannel.id,
      name: 'Refreshed channel',
      streamUri: Uri.parse('https://new-stream.invalid/live'),
      sourceId: source.id,
      allowsPrivateNetwork: false,
      group: 'Updated',
    );
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [oldChannel],
      ),
      refreshAccess: SourceRefreshAccess(
        source: source,
        username: 'saved-user',
        password: 'saved-password',
      ),
    );
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        refreshResult: PlaylistImportResult(
          source: source,
          channels: [refreshedChannel],
          warnings: const [],
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);
    container.read(libraryControllerProvider.notifier).select(oldChannel);

    await container
        .read(libraryControllerProvider.notifier)
        .refreshSource(source.id);

    final state = container.read(libraryControllerProvider);
    expect(state.selectedChannel?.name, 'Refreshed channel');
    expect(state.selectedChannel?.streamUri.host, 'new-stream.invalid');
    expect(state.sources.single.name, 'Provider');
    expect(store.savedUsername, 'saved-user');
    expect(store.savedPassword, 'saved-password');
    expect(store.saveCount, 1);
  });

  test('a failed refresh leaves the working snapshot untouched', () async {
    final oldChannel = _channel('working');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [oldChannel],
      ),
      refreshAccess: SourceRefreshAccess(
        source: _source(),
        username: 'saved-user',
        password: 'saved-password',
      ),
    );
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        refreshError: Exception('Synthetic refresh failure.'),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .refreshSource('source-1');

    final state = container.read(libraryControllerProvider);
    expect(state.channels.single.id, 'working');
    expect(state.error, contains('Synthetic refresh failure'));
    expect(store.saveCount, 0);
  });

  test('rename and delete update storage before UI state', () async {
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [_channel('one')],
      ),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    await controller.renameSource('source-1', 'Renamed');
    expect(store.renamed, ('source-1', 'Renamed'));
    expect(
      container.read(libraryControllerProvider).sources.single.name,
      'Renamed',
    );

    await controller.deleteSource('source-1');
    expect(store.deletedSourceId, 'source-1');
    expect(container.read(libraryControllerProvider).sources, isEmpty);
    expect(container.read(libraryControllerProvider).channels, isEmpty);
  });
}

ProviderContainer _container({
  required LibraryStore store,
  PlaylistImportService? importer,
}) => ProviderContainer(
  overrides: [
    libraryStoreProvider.overrideWithValue(store),
    if (importer != null)
      playlistImportServiceProvider.overrideWithValue(importer),
  ],
);

Future<void> _waitForLoad(ProviderContainer container) async {
  container.read(libraryControllerProvider);
  await _waitUntil(() => !container.read(libraryControllerProvider).isLoading);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

PlaylistSource _source() => PlaylistSource(
  id: 'source-1',
  name: 'Provider',
  kind: PlaylistSourceKind.xtream,
  location: 'https://provider.invalid',
  allowsPrivateNetwork: false,
  importedAt: DateTime.utc(2026, 7, 15),
);

LibrarySource _librarySource() => LibrarySource.fromImported(_source());

Channel _channel(String id) => Channel(
  id: id,
  name: 'Channel $id',
  streamUri: Uri.parse('https://stream.invalid/$id'),
  sourceId: 'source-1',
  allowsPrivateNetwork: false,
  group: 'News',
);

final class _FakeLibraryStore implements LibraryStore {
  _FakeLibraryStore({
    this.initial = const LibrarySnapshot.empty(),
    this.loadError,
    this.saveGate,
    this.saveError,
    this.refreshAccess,
  });

  final LibrarySnapshot initial;
  final Exception? loadError;
  final Completer<void>? saveGate;
  final Exception? saveError;
  final SourceRefreshAccess? refreshAccess;
  bool saveStarted = false;
  PlaylistSource? savedSource;
  String? savedUsername;
  String? savedPassword;
  var saveCount = 0;
  var resetCount = 0;
  (String, String)? renamed;
  String? deletedSourceId;

  @override
  Future<LibrarySnapshot> load() async {
    if (loadError case final error?) throw error;
    return initial;
  }

  @override
  Future<void> replaceSourceSnapshot({
    required PlaylistSource source,
    required List<Channel> channels,
    String? username,
    String? password,
  }) async {
    saveCount++;
    saveStarted = true;
    savedSource = source;
    savedUsername = username;
    savedPassword = password;
    await saveGate?.future;
    if (saveError case final error?) throw error;
  }

  @override
  Future<void> reset() async => resetCount++;

  @override
  Future<SourceRefreshAccess?> readSourceRefreshAccess(String sourceId) async =>
      refreshAccess;

  @override
  Future<void> renameSource({
    required String sourceId,
    required String name,
  }) async => renamed = (sourceId, name);

  @override
  Future<void> deleteSource(String sourceId) async =>
      deletedSourceId = sourceId;
}

final class _FakePlaylistImportService extends PlaylistImportService {
  _FakePlaylistImportService({
    this.result,
    this.refreshResult,
    this.refreshError,
  });

  final PlaylistImportResult? result;
  final PlaylistImportResult? refreshResult;
  final Exception? refreshError;

  @override
  Future<PlaylistImportResult> fromUrl(
    Uri uri, {
    required bool allowPrivateNetwork,
  }) async => result!;

  @override
  Future<PlaylistImportResult> fromXtream({
    required Uri server,
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async => result!;

  @override
  Future<PlaylistImportResult> refresh(
    PlaylistSource source, {
    String? username,
    String? password,
  }) async {
    if (refreshError case final error?) throw error;
    return refreshResult!;
  }
}
