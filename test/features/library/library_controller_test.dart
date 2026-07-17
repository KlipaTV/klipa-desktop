import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/data/local_epg_service.dart';
import 'package:klipa_player_windows/data/playlist_import_service.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/channel_identity.dart';
import 'package:klipa_player_windows/domain/channel_schedule.dart';
import 'package:klipa_player_windows/domain/library_navigation.dart';
import 'package:klipa_player_windows/domain/library_source.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
import 'package:klipa_player_windows/domain/programme.dart';
import 'package:klipa_player_windows/features/library/library_controller.dart';

void main() {
  test(
    'restores the encrypted library without autoplaying a channel',
    () async {
      final store = _FakeLibraryStore(
        initial: LibrarySnapshot(
          sources: [_librarySource()],
          channels: [_channel('saved')],
          favoriteChannels: const {(sourceId: 'source-1', channelId: 'saved')},
          navigation: const LibraryNavigation(
            selectedSourceId: 'source-1',
            selectedGroup: 'News',
            lastChannel: (sourceId: 'source-1', channelId: 'saved'),
          ),
        ),
      );
      final container = _container(store: store);
      addTearDown(container.dispose);

      await _waitForLoad(container);
      final state = container.read(libraryControllerProvider);

      expect(state.sources.single.id, 'source-1');
      expect(state.channels.single.id, 'saved');
      expect(state.isFavorite(state.channels.single), isTrue);
      expect(state.selectedSourceId, 'source-1');
      expect(state.selectedGroup, 'News');
      expect(state.resumeChannel?.id, 'saved');
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
        favoriteChannels: {
          (sourceId: oldChannel.sourceId, channelId: oldChannel.id),
        },
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
    expect(state.resumeChannel?.name, 'Refreshed channel');
    expect(state.isFavorite(refreshedChannel), isTrue);
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
        favoriteChannels: const {(sourceId: 'source-1', channelId: 'one')},
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
    expect(container.read(libraryControllerProvider).favoriteChannels, isEmpty);
  });

  test(
    'favorite changes publish only after encrypted storage succeeds',
    () async {
      final favoriteGate = Completer<void>();
      final channel = _channel('one');
      final store = _FakeLibraryStore(
        initial: LibrarySnapshot(
          sources: [_librarySource()],
          channels: [channel],
        ),
        favoriteGate: favoriteGate,
      );
      final container = _container(store: store);
      addTearDown(container.dispose);
      await _waitForLoad(container);
      final controller = container.read(libraryControllerProvider.notifier);

      final toggle = controller.toggleFavorite(channel);
      await _waitUntil(() => store.favoriteWrites.isNotEmpty);
      expect(
        container.read(libraryControllerProvider).isFavorite(channel),
        isFalse,
      );

      favoriteGate.complete();
      await toggle;
      expect(store.favoriteWrites.single, ('source-1', 'one', true));
      expect(
        container.read(libraryControllerProvider).isFavorite(channel),
        isTrue,
      );

      await controller.toggleFavorite(channel);
      expect(store.favoriteWrites.last, ('source-1', 'one', false));
      expect(
        container.read(libraryControllerProvider).isFavorite(channel),
        isFalse,
      );
    },
  );

  test('a failed favorite write leaves the visible state unchanged', () async {
    final channel = _channel('one');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [channel],
      ),
      favoriteError: Exception('Synthetic favorite failure.'),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .toggleFavorite(channel);

    final state = container.read(libraryControllerProvider);
    expect(state.isFavorite(channel), isFalse);
    expect(state.error, contains('Synthetic favorite failure'));
  });

  test('source, group, and channel navigation is queued in order', () async {
    final channel = _channel('one');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [channel],
      ),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    controller.filterSource('source-1');
    controller.filterGroup('News');
    controller.select(channel);
    await _waitUntil(() => store.navigationWrites.length == 3);

    final saved = store.navigationWrites.last;
    expect(saved.selectedSourceId, 'source-1');
    expect(saved.selectedGroup, 'News');
    expect(saved.lastChannel, (sourceId: 'source-1', channelId: 'one'));
  });

  test('a failed navigation save does not undo the user action', () async {
    final channel = _channel('one');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [channel],
      ),
      navigationError: Exception('Synthetic navigation failure.'),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);

    container.read(libraryControllerProvider.notifier).select(channel);
    await _waitUntil(
      () => container.read(libraryControllerProvider).error != null,
    );

    final state = container.read(libraryControllerProvider);
    expect(state.selectedChannel, channel);
    expect(state.error, contains('Synthetic navigation failure'));
  });

  test('deleting a source clears a stale category filter', () async {
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource(), _librarySource(id: 'source-2')],
        channels: [
          _channel('one'),
          _channel('two', sourceId: 'source-2', group: 'Sports'),
        ],
      ),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);
    controller.filterGroup('Sports');

    await controller.deleteSource('source-2');

    final state = container.read(libraryControllerProvider);
    expect(state.selectedGroup, isNull);
    expect(state.selectedSourceId, isNull);
    expect(state.channels.single.id, 'one');
  });

  test('deleting a source keeps a category filter that survives', () async {
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource(), _librarySource(id: 'source-2')],
        channels: [
          _channel('one'),
          _channel('two', sourceId: 'source-2', group: 'Sports'),
        ],
      ),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);
    controller.filterGroup('News');

    await controller.deleteSource('source-2');

    expect(container.read(libraryControllerProvider).selectedGroup, 'News');
  });

  test('reset cannot be raced by selection or navigation saves', () async {
    final resetGate = Completer<void>();
    final channel = _channel('one');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [channel],
      ),
      resetGate: resetGate,
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    final reset = controller.resetLibrary();
    await _waitUntil(() => store.resetStarted);
    controller.select(channel);
    controller.filterSource('source-1');
    controller.filterGroup('News');

    expect(container.read(libraryControllerProvider).selectedChannel, isNull);
    resetGate.complete();
    await reset;

    final state = container.read(libraryControllerProvider);
    expect(store.navigationWrites, isEmpty);
    expect(state.selectedChannel, isNull);
    expect(state.selectedSourceId, isNull);
    expect(state.message, 'App data was reset.');
  });

  test('a concurrent import attempt is rejected with a notice', () async {
    final saveGate = Completer<void>();
    final store = _FakeLibraryStore(saveGate: saveGate);
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        result: PlaylistImportResult(
          source: _source(),
          channels: [_channel('new')],
          warnings: const [],
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    final import = controller.importUrl(
      'https://provider.invalid/list.m3u',
      allowPrivateNetwork: false,
    );
    await _waitUntil(() => store.saveStarted);

    await controller.importUrl(
      'https://other.invalid/list.m3u',
      allowPrivateNetwork: false,
    );
    expect(
      container.read(libraryControllerProvider).error,
      'Another operation is in progress.',
    );

    saveGate.complete();
    await import;

    final state = container.read(libraryControllerProvider);
    expect(state.error, isNull);
    expect(state.message, 'Imported 1 channels.');
    expect(store.saveCount, 1);
  });

  test('an import rejects a playlist address without a valid shape', () async {
    final store = _FakeLibraryStore();
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .importUrl('not a playlist address', allowPrivateNetwork: false);

    final state = container.read(libraryControllerProvider);
    expect(state.error, 'Enter a valid playlist address.');
    expect(state.isImporting, isFalse);
    expect(store.saveCount, 0);
  });

  test('favorites for different channels persist without fan-out', () async {
    final first = _channel('one');
    final second = _channel('two');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [first, second],
      ),
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    await Future.wait([
      controller.toggleFavorite(first),
      controller.toggleFavorite(second),
    ]);

    final state = container.read(libraryControllerProvider);
    expect(state.isFavorite(first), isTrue);
    expect(state.isFavorite(second), isTrue);
    expect(
      store.favoriteWrites,
      containsAll(const [('source-1', 'one', true), ('source-1', 'two', true)]),
    );
    // Writes are serialized, so a burst never opens more than one at a time.
    expect(store.maxFavoriteInFlight, 1);
  });

  test('rapid duplicate favorite toggles write once', () async {
    final favoriteGate = Completer<void>();
    final channel = _channel('one');
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [channel],
      ),
      favoriteGate: favoriteGate,
    );
    final container = _container(store: store);
    addTearDown(container.dispose);
    await _waitForLoad(container);
    final controller = container.read(libraryControllerProvider.notifier);

    final first = controller.toggleFavorite(channel);
    final second = controller.toggleFavorite(channel);
    favoriteGate.complete();
    await first;
    await second;

    expect(store.favoriteWrites.single, ('source-1', 'one', true));
    expect(
      container.read(libraryControllerProvider).isFavorite(channel),
      isTrue,
    );
  });

  test('a failed guide download is reported with the import result', () async {
    final store = _FakeEpgLibraryStore();
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        result: PlaylistImportResult(
          source: _source(),
          channels: [_channel('new')],
          warnings: const [],
        ),
      ),
      epg: _FakeEpgService(
        error: Exception(
          'guide failed https://user:password@guide.invalid/feed?token=secret',
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .importUrl(
          'https://provider.invalid/list.m3u',
          allowPrivateNetwork: false,
          guideUrl: 'https://guide.invalid/guide.xml',
        );

    final state = container.read(libraryControllerProvider);
    expect(state.channels.single.id, 'new');
    expect(state.message, contains('Imported 1 channels.'));
    expect(state.message, contains('The guide could not be loaded'));
    expect(state.message, isNot(contains('password')));
    expect(state.message, isNot(contains('secret')));
  });

  test('a guide refresh publishes now and next schedules', () async {
    final programme = Programme(
      sourceId: 'source-1',
      guideId: 'guide-1',
      title: 'Now showing',
      startUtc: DateTime.utc(2026, 7, 17, 6),
      endUtc: DateTime.utc(2026, 7, 17, 8),
    );
    final store = _FakeEpgLibraryStore(
      schedulesResult: {
        (sourceId: 'source-1', channelId: 'new'): ChannelSchedule(
          current: programme,
        ),
      },
    );
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        result: PlaylistImportResult(
          source: _source(),
          channels: [_channel('new')],
          warnings: const [],
        ),
      ),
      epg: _FakeEpgService(
        result: LocalEpgRefreshResult(
          programmes: [programme],
          refreshedAt: DateTime.utc(2026, 7, 17, 7),
          expiresAt: DateTime.utc(2026, 7, 17, 13),
          skippedEntries: 0,
          outsideWindowEntries: 0,
          truncated: false,
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .importUrl(
          'https://provider.invalid/list.m3u',
          allowPrivateNetwork: false,
          guideUrl: 'https://guide.invalid/guide.xml',
        );

    final state = container.read(libraryControllerProvider);
    expect(store.programmeWrites.single, ('source-1', 1));
    expect(
      state.scheduleFor(state.channels.single)?.current?.title,
      'Now showing',
    );
    expect(state.message, 'Imported 1 channels.');
  });

  test('a truncated guide is reported with the import result', () async {
    final programme = Programme(
      sourceId: 'source-1',
      guideId: 'guide-1',
      title: 'Now showing',
      startUtc: DateTime.utc(2026, 7, 17, 6),
      endUtc: DateTime.utc(2026, 7, 17, 8),
    );
    final store = _FakeEpgLibraryStore();
    final container = _container(
      store: store,
      importer: _FakePlaylistImportService(
        result: PlaylistImportResult(
          source: _source(),
          channels: [_channel('new')],
          warnings: const [],
        ),
      ),
      epg: _FakeEpgService(
        result: LocalEpgRefreshResult(
          programmes: [programme],
          refreshedAt: DateTime.utc(2026, 7, 17, 7),
          expiresAt: DateTime.utc(2026, 7, 17, 13),
          skippedEntries: 0,
          outsideWindowEntries: 0,
          truncated: true,
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .importUrl(
          'https://provider.invalid/list.m3u',
          allowPrivateNetwork: false,
          guideUrl: 'https://guide.invalid/guide.xml',
        );

    final state = container.read(libraryControllerProvider);
    expect(state.message, contains('Imported 1 channels.'));
    expect(state.message, contains('loaded only in part'));
  });

  test('a refresh drops schedules for channels that disappeared', () async {
    final store = _FakeLibraryStore(
      initial: LibrarySnapshot(
        sources: [_librarySource()],
        channels: [_channel('working'), _channel('gone')],
        schedules: const {
          (sourceId: 'source-1', channelId: 'working'): ChannelSchedule(),
          (sourceId: 'source-1', channelId: 'gone'): ChannelSchedule(),
        },
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
        refreshResult: PlaylistImportResult(
          source: _source(),
          channels: [_channel('working')],
          warnings: const [],
        ),
      ),
    );
    addTearDown(container.dispose);
    await _waitForLoad(container);

    await container
        .read(libraryControllerProvider.notifier)
        .refreshSource('source-1');

    final state = container.read(libraryControllerProvider);
    expect(state.schedules.keys, [
      (sourceId: 'source-1', channelId: 'working'),
    ]);
  });
}

ProviderContainer _container({
  required LibraryStore store,
  PlaylistImportService? importer,
  LocalEpgService? epg,
}) => ProviderContainer(
  overrides: [
    libraryStoreProvider.overrideWithValue(store),
    if (importer != null)
      playlistImportServiceProvider.overrideWithValue(importer),
    if (epg != null) localEpgServiceProvider.overrideWithValue(epg),
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

PlaylistSource _source({String id = 'source-1'}) => PlaylistSource(
  id: id,
  name: 'Provider',
  kind: PlaylistSourceKind.xtream,
  location: 'https://provider.invalid',
  allowsPrivateNetwork: false,
  importedAt: DateTime.utc(2026, 7, 15),
);

LibrarySource _librarySource({String id = 'source-1'}) =>
    LibrarySource.fromImported(_source(id: id));

Channel _channel(
  String id, {
  String sourceId = 'source-1',
  String group = 'News',
}) => Channel(
  id: id,
  name: 'Channel $id',
  streamUri: Uri.parse('https://stream.invalid/$id'),
  sourceId: sourceId,
  allowsPrivateNetwork: false,
  group: group,
);

final class _FakeLibraryStore implements LibraryStore {
  _FakeLibraryStore({
    this.initial = const LibrarySnapshot.empty(),
    this.loadError,
    this.saveGate,
    this.saveError,
    this.refreshAccess,
    this.favoriteGate,
    this.favoriteError,
    this.navigationError,
    this.resetGate,
  });

  final LibrarySnapshot initial;
  final Exception? loadError;
  final Completer<void>? saveGate;
  final Exception? saveError;
  final SourceRefreshAccess? refreshAccess;
  final Completer<void>? favoriteGate;
  final Exception? favoriteError;
  final Exception? navigationError;
  final Completer<void>? resetGate;
  bool resetStarted = false;
  bool saveStarted = false;
  PlaylistSource? savedSource;
  String? savedUsername;
  String? savedPassword;
  var saveCount = 0;
  var resetCount = 0;
  (String, String)? renamed;
  String? deletedSourceId;
  final favoriteWrites = <(String, String, bool)>[];
  final navigationWrites = <LibraryNavigation>[];
  var favoriteInFlight = 0;
  var maxFavoriteInFlight = 0;

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
    String? guideLocation,
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
  Future<void> reset() async {
    resetStarted = true;
    await resetGate?.future;
    resetCount++;
  }

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

  @override
  Future<void> setFavorite({
    required String sourceId,
    required String channelId,
    required bool favorite,
  }) async {
    favoriteInFlight++;
    if (favoriteInFlight > maxFavoriteInFlight) {
      maxFavoriteInFlight = favoriteInFlight;
    }
    favoriteWrites.add((sourceId, channelId, favorite));
    try {
      await favoriteGate?.future;
      if (favoriteError case final error?) throw error;
    } finally {
      favoriteInFlight--;
    }
  }

  @override
  Future<void> saveNavigation(LibraryNavigation navigation) async {
    navigationWrites.add(navigation);
    if (navigationError case final error?) throw error;
  }
}

final class _FakeEpgLibraryStore extends _FakeLibraryStore
    implements EpgLibraryStore {
  _FakeEpgLibraryStore({this.schedulesResult = const {}});

  final Map<ChannelIdentity, ChannelSchedule> schedulesResult;
  final programmeWrites = <(String, int)>[];

  @override
  Future<Map<ChannelIdentity, ChannelSchedule>> replaceProgrammeSnapshot({
    required String sourceId,
    required List<Programme> programmes,
    required DateTime refreshedAt,
    required DateTime expiresAt,
  }) async {
    programmeWrites.add((sourceId, programmes.length));
    return schedulesResult;
  }

  @override
  Future<Map<ChannelIdentity, ChannelSchedule>> loadNowNext(
    DateTime nowUtc,
  ) async => schedulesResult;
}

final class _FakeEpgService extends LocalEpgService {
  _FakeEpgService({this.error, this.result});

  final Exception? error;
  final LocalEpgRefreshResult? result;

  @override
  Future<LocalEpgRefreshResult> refresh({
    required PlaylistSource source,
    required DateTime nowUtc,
    Uri? attachedGuideUri,
    String? username,
    String? password,
  }) async {
    if (error case final error?) throw error;
    return result!;
  }
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
