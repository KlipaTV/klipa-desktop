import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/data/playlist_import_service.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
import 'package:klipa_player_windows/features/library/library_controller.dart';

void main() {
  test(
    'restores the encrypted library without autoplaying a channel',
    () async {
      final store = _FakeLibraryStore(
        initial: LibrarySnapshot(
          sources: [_source()],
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
      importer: _FakePlaylistImportService(result),
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
        sources: [_source()],
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
      importer: _FakePlaylistImportService(result),
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
  });

  final LibrarySnapshot initial;
  final Exception? loadError;
  final Completer<void>? saveGate;
  final Exception? saveError;
  bool saveStarted = false;
  PlaylistSource? savedSource;
  String? savedUsername;
  String? savedPassword;
  var resetCount = 0;

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
    saveStarted = true;
    savedSource = source;
    savedUsername = username;
    savedPassword = password;
    await saveGate?.future;
    if (saveError case final error?) throw error;
  }

  @override
  Future<void> reset() async => resetCount++;
}

final class _FakePlaylistImportService extends PlaylistImportService {
  _FakePlaylistImportService(this.result);

  final PlaylistImportResult result;

  @override
  Future<PlaylistImportResult> fromUrl(
    Uri uri, {
    required bool allowPrivateNetwork,
  }) async => result;

  @override
  Future<PlaylistImportResult> fromXtream({
    required Uri server,
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async => result;
}
