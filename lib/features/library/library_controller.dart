import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/network_policy.dart';
import '../../core/security/sensitive_data_redactor.dart';
import '../../data/encrypted_library_database.dart';
import '../../data/library_store.dart';
import '../../data/local_epg_service.dart';
import '../../data/playlist_import_service.dart';
import '../../domain/channel.dart';
import '../../domain/channel_identity.dart';
import '../../domain/channel_schedule.dart';
import '../../domain/library_navigation.dart';
import '../../domain/library_source.dart';
import '../../domain/playlist_source.dart';
import 'library_state.dart';

final playlistImportServiceProvider = Provider<PlaylistImportService>(
  (ref) => PlaylistImportService(),
);

final localEpgServiceProvider = Provider<LocalEpgService>(
  (ref) => LocalEpgService(),
);

final libraryStoreProvider = Provider<LibraryStore>(
  (ref) => Platform.isWindows || Platform.isLinux
      ? EncryptedLibraryStore()
      : const DisabledLibraryStore(),
);

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  var _disposed = false;
  final _favoriteWrites = <ChannelIdentity>{};
  Future<void> _navigationWrites = Future.value();
  Future<void> _favoriteWriteChain = Future.value();

  PlaylistImportService get _importer =>
      ref.read(playlistImportServiceProvider);

  LibraryStore get _store => ref.read(libraryStoreProvider);

  @override
  LibraryState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_restoreLibrary));
    return LibraryState(isLoading: true);
  }

  Future<void> importUrl(
    String value, {
    required bool allowPrivateNetwork,
    String? guideUrl,
  }) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !_isValidHttpShape(uri)) {
      state = state.copyWith(error: 'Enter a valid playlist address.');
      return;
    }
    final normalizedGuide = guideUrl?.trim();
    if (normalizedGuide != null && normalizedGuide.isNotEmpty) {
      final guideUri = Uri.tryParse(normalizedGuide);
      if (guideUri == null || !_isValidHttpShape(guideUri)) {
        state = state.copyWith(error: 'Enter a valid XMLTV guide address.');
        return;
      }
    }
    await _import(
      () => _importer.fromUrl(uri, allowPrivateNetwork: allowPrivateNetwork),
      operationMessage: 'Importing channels…',
      guideLocation: normalizedGuide?.isEmpty ?? true ? null : normalizedGuide,
    );
  }

  Future<void> importFile() async {
    await _import(
      _importer.fromFilePicker,
      operationMessage: 'Importing channels…',
    );
  }

  Future<void> importXtream({
    required String server,
    required String username,
    required String password,
    required bool allowPrivateNetwork,
  }) async {
    final uri = Uri.tryParse(server.trim());
    if (uri == null) {
      state = state.copyWith(error: 'Enter a valid Xtream server address.');
      return;
    }
    await _import(
      () => _importer.fromXtream(
        server: uri,
        username: username.trim(),
        password: password,
        allowPrivateNetwork: allowPrivateNetwork,
      ),
      operationMessage: 'Signing in and importing channels…',
      username: username.trim(),
      password: password,
    );
  }

  void search(String value) {
    state = state.copyWith(query: value);
  }

  void filterGroup(String? value) {
    if (state.isResetting) return;
    state = state.copyWith(selectedGroup: value, clearGroup: value == null);
    _queueNavigationSave();
  }

  void filterSource(String? sourceId) {
    if (state.isResetting) return;
    final sourceChannels = sourceId == null
        ? state.channels
        : state.channels
              .where((channel) => channel.sourceId == sourceId)
              .toList(growable: false);
    final keepGroup =
        state.selectedGroup == null ||
        sourceChannels.any((channel) => channel.group == state.selectedGroup);
    state = state.copyWith(
      selectedSourceId: sourceId,
      clearSource: sourceId == null,
      clearGroup: !keepGroup,
    );
    _queueNavigationSave();
  }

  void setFavoritesOnly(bool value) {
    state = state.copyWith(favoritesOnly: value);
  }

  Future<void> toggleFavorite(Channel channel) async {
    final identity = (sourceId: channel.sourceId, channelId: channel.id);
    if (!_favoriteWrites.add(identity)) return;
    try {
      if (state.isLoading || state.isImporting || state.isResetting) return;
      final favorite = !state.favoriteChannels.contains(identity);
      // Serialize the store writes so a burst of toggles across many channels
      // does not spawn one isolate (and one key derivation) per channel at once.
      final write = _favoriteWriteChain.then((_) async {
        await _navigationWrites;
        await _store.setFavorite(
          sourceId: identity.sourceId,
          channelId: identity.channelId,
          favorite: favorite,
        );
      });
      _favoriteWriteChain = write.then((_) {}, onError: (_) {});
      await write;
      if (_disposed) return;
      final favorites = state.favoriteChannels.toSet();
      favorite ? favorites.add(identity) : favorites.remove(identity);
      state = state.copyWith(
        favoriteChannels: Set.unmodifiable(favorites),
        clearError: true,
      );
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        error: const SensitiveDataRedactor().text(error.toString()),
        clearMessage: true,
      );
    } finally {
      _favoriteWrites.remove(identity);
    }
  }

  void select(Channel channel) {
    if (state.isResetting) return;
    state = state.copyWith(
      selectedChannel: channel,
      lastChannelIdentity: (sourceId: channel.sourceId, channelId: channel.id),
      clearError: true,
    );
    _queueNavigationSave();
  }

  void dismissNotices() {
    state = state.copyWith(clearMessage: true, clearError: true);
  }

  Future<void> refreshActiveSource() async {
    final sourceId =
        state.selectedSourceId ??
        state.selectedChannel?.sourceId ??
        (state.sources.length == 1 ? state.sources.single.id : null);
    if (sourceId == null) {
      state = state.copyWith(
        error: 'Select a source before refreshing.',
        clearMessage: true,
      );
      return;
    }
    await refreshSource(sourceId);
  }

  Future<void> refreshSource(String sourceId) async {
    if (_operationInProgress) return;
    _startOperation('Refreshing channels…');
    try {
      await _navigationWrites;
      final access = await _store.readSourceRefreshAccess(sourceId);
      if (access == null) {
        throw const LibraryDatabaseException('The source no longer exists.');
      }
      final result = await _importer.refresh(
        access.source,
        username: access.username,
        password: access.password,
      );
      await _store.replaceSourceSnapshot(
        source: result.source,
        channels: result.channels,
        username: access.username,
        password: access.password,
        guideLocation: access.guideLocation,
      );
      final guide = await _refreshGuide(
        result.source,
        username: access.username,
        password: access.password,
        guideLocation: access.guideLocation,
      );
      if (_disposed) return;
      _publishSourceSnapshot(result, verb: 'Refreshed', guide: guide);
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  Future<void> renameSource(String sourceId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(error: 'Enter a valid source name.');
      return;
    }
    if (_operationInProgress) return;
    _startOperation('Renaming source…');
    try {
      await _navigationWrites;
      await _store.renameSource(sourceId: sourceId, name: normalized);
      if (_disposed) return;
      state = state.copyWith(
        sources: List.unmodifiable(<LibrarySource>[
          for (final source in state.sources)
            source.id == sourceId ? source.copyWith(name: normalized) : source,
        ]..sort(_compareSources)),
        isImporting: false,
        clearOperationMessage: true,
        message: 'Renamed source.',
      );
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  Future<void> deleteSource(String sourceId) async {
    if (_operationInProgress) return;
    _startOperation('Deleting source…');
    try {
      await _navigationWrites;
      await _store.deleteSource(sourceId);
      if (_disposed) return;
      final channels = state.channels
          .where((channel) => channel.sourceId != sourceId)
          .toList(growable: false);
      final selectedWasDeleted = state.selectedChannel?.sourceId == sourceId;
      final lastChannelWasDeleted =
          state.lastChannelIdentity?.sourceId == sourceId;
      final sourceFilterWasDeleted = state.selectedSourceId == sourceId;
      final relevantChannels = state.selectedSourceId == null
          ? channels
          : channels
                .where((channel) => channel.sourceId == state.selectedSourceId)
                .toList(growable: false);
      final keepSelectedGroup =
          state.selectedGroup == null ||
          relevantChannels.any(
            (channel) => channel.group == state.selectedGroup,
          );
      state = state.copyWith(
        sources: List.unmodifiable(
          state.sources.where((source) => source.id != sourceId),
        ),
        channels: List.unmodifiable(channels),
        groups: LibraryState.deriveGroups(channels),
        favoriteChannels: Set.unmodifiable(
          state.favoriteChannels.where(
            (favorite) => favorite.sourceId != sourceId,
          ),
        ),
        schedules: Map.unmodifiable(
          Map<ChannelIdentity, ChannelSchedule>.of(state.schedules)
            ..removeWhere((identity, _) => identity.sourceId == sourceId),
        ),
        clearSelection: selectedWasDeleted,
        clearLastChannel: lastChannelWasDeleted,
        clearSource: sourceFilterWasDeleted,
        clearGroup: !keepSelectedGroup,
        isImporting: false,
        clearOperationMessage: true,
        message: 'Deleted source.',
      );
      _queueNavigationSave();
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  bool get _operationInProgress =>
      state.isLoading ||
      state.isImporting ||
      state.isResetting ||
      _favoriteWrites.isNotEmpty;

  void _startOperation(String operationMessage) {
    state = state.copyWith(
      isImporting: true,
      operationMessage: operationMessage,
      clearError: true,
      clearMessage: true,
    );
  }

  void _failOperation(Object error) {
    if (_disposed) return;
    state = state.copyWith(
      isImporting: false,
      clearOperationMessage: true,
      error: const SensitiveDataRedactor().text(error.toString()),
    );
  }

  Future<void> resetLibrary() async {
    if (_operationInProgress) return;
    state = state.copyWith(
      clearSelection: true,
      isResetting: true,
      recoveryRequired: false,
      clearError: true,
      clearMessage: true,
    );
    try {
      await _navigationWrites;
      await _store.reset();
      if (_disposed) return;
      state = LibraryState(message: 'App data was reset.');
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isResetting: false,
        error: const SensitiveDataRedactor().text(error.toString()),
      );
    }
  }

  Future<void> _import(
    Future<PlaylistImportResult?> Function() operation, {
    required String operationMessage,
    String? username,
    String? password,
    String? guideLocation,
  }) async {
    if (_operationInProgress) {
      state = state.copyWith(
        error: 'Another operation is in progress.',
        clearMessage: true,
      );
      return;
    }
    _startOperation(operationMessage);
    try {
      final result = await operation();
      if (_disposed) return;
      if (result == null) {
        state = state.copyWith(isImporting: false, clearOperationMessage: true);
        return;
      }

      await _navigationWrites;
      await _store.replaceSourceSnapshot(
        source: result.source,
        channels: result.channels,
        username: username,
        password: password,
        guideLocation: guideLocation,
      );
      final guide = await _refreshGuide(
        result.source,
        username: username,
        password: password,
        guideLocation: guideLocation,
      );
      if (_disposed) return;

      _publishSourceSnapshot(result, verb: 'Imported', guide: guide);
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  void _publishSourceSnapshot(
    PlaylistImportResult result, {
    required String verb,
    required _GuideRefresh guide,
  }) {
    final otherChannels = state.channels
        .where((channel) => channel.sourceId != result.source.id)
        .toList();
    final previousSource = state.sources
        .where((source) => source.id == result.source.id)
        .firstOrNull;
    final otherSources = state.sources
        .where((source) => source.id != result.source.id)
        .toList();
    final channels = [...otherChannels, ...result.channels]
      ..sort((left, right) => left.name.compareTo(right.name));
    final refreshedChannelIds = {
      for (final channel in result.channels) channel.id,
    };
    final favorites = state.favoriteChannels.where(
      (favorite) =>
          favorite.sourceId != result.source.id ||
          refreshedChannelIds.contains(favorite.channelId),
    );
    final source = LibrarySource.fromImported(
      result.source,
      refreshedAt: DateTime.now().toUtc(),
    );
    final selectedId = state.selectedChannel?.sourceId == result.source.id
        ? state.selectedChannel?.id
        : null;
    Channel? refreshedSelection;
    if (selectedId != null) {
      for (final channel in result.channels) {
        if (channel.id == selectedId) {
          refreshedSelection = channel;
          break;
        }
      }
    }
    final lastIdentity = state.lastChannelIdentity;
    final keepLastChannel =
        lastIdentity == null ||
        lastIdentity.sourceId != result.source.id ||
        refreshedChannelIds.contains(lastIdentity.channelId);
    final relevantChannels = state.selectedSourceId == null
        ? channels
        : channels
              .where((channel) => channel.sourceId == state.selectedSourceId)
              .toList(growable: false);
    final keepSelectedGroup =
        state.selectedGroup == null ||
        relevantChannels.any((channel) => channel.group == state.selectedGroup);
    final warningSuffix = result.warnings.isEmpty
        ? ''
        : ' ${result.warnings.length} entries were skipped or limited.';
    final guideSuffix = guide.error == null
        ? ''
        : ' The guide could not be loaded: ${guide.error}';
    final guideTruncatedSuffix = guide.truncated
        ? ' The guide was too large and was loaded only in part.'
        : '';
    final schedules =
        guide.schedules ??
        Map<ChannelIdentity, ChannelSchedule>.unmodifiable(
          Map<ChannelIdentity, ChannelSchedule>.of(state.schedules)
            ..removeWhere(
              (identity, _) =>
                  identity.sourceId == result.source.id &&
                  !refreshedChannelIds.contains(identity.channelId),
            ),
        );
    final sources = <LibrarySource>[
      ...otherSources,
      previousSource == null
          ? source
          : source.copyWith(name: previousSource.name),
    ]..sort(_compareSources);
    state = state.copyWith(
      sources: List.unmodifiable(sources),
      channels: List.unmodifiable(channels),
      favoriteChannels: Set.unmodifiable(favorites),
      schedules: schedules,
      groups: LibraryState.deriveGroups(channels),
      selectedChannel: refreshedSelection,
      clearSelection: selectedId != null && refreshedSelection == null,
      clearLastChannel: !keepLastChannel,
      clearGroup: !keepSelectedGroup,
      isImporting: false,
      clearOperationMessage: true,
      clearError: true,
      message: '$verb ${result.channels.length} channels.$warningSuffix'
          '$guideSuffix$guideTruncatedSuffix',
    );
    _queueNavigationSave();
  }

  Future<void> _restoreLibrary() async {
    try {
      final snapshot = await _store.load();
      if (_disposed) return;
      final channels = snapshot.channels.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      final sources = snapshot.sources.toList()..sort(_compareSources);
      state = state.copyWith(
        sources: List.unmodifiable(sources),
        channels: List.unmodifiable(channels),
        favoriteChannels: Set.unmodifiable(snapshot.favoriteChannels),
        schedules: Map.unmodifiable(snapshot.schedules),
        selectedSourceId: snapshot.navigation.selectedSourceId,
        selectedGroup: snapshot.navigation.selectedGroup,
        lastChannelIdentity: snapshot.navigation.lastChannel,
        groups: LibraryState.deriveGroups(channels),
        isLoading: false,
        recoveryRequired: false,
        clearError: true,
      );
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        recoveryRequired: true,
        error: const SensitiveDataRedactor().text(error.toString()),
      );
    }
  }

  Future<_GuideRefresh> _refreshGuide(
    PlaylistSource source, {
    String? username,
    String? password,
    String? guideLocation,
  }) async {
    final store = _store;
    if (source.kind != PlaylistSourceKind.xtream && guideLocation == null ||
        store is! EpgLibraryStore) {
      return (schedules: null, error: null, truncated: false);
    }
    final epgStore = store as EpgLibraryStore;
    try {
      final guide = await ref
          .read(localEpgServiceProvider)
          .refresh(
            source: source,
            nowUtc: DateTime.now().toUtc(),
            username: username,
            password: password,
            attachedGuideUri: guideLocation == null
                ? null
                : Uri.parse(guideLocation),
          );
      final schedules = await epgStore.replaceProgrammeSnapshot(
        sourceId: source.id,
        programmes: guide.programmes,
        refreshedAt: guide.refreshedAt,
        expiresAt: guide.expiresAt,
      );
      return (schedules: schedules, error: null, truncated: guide.truncated);
    } on Object catch (error) {
      return (
        schedules: null,
        error: const SensitiveDataRedactor().text(error.toString()),
        truncated: false,
      );
    }
  }

  void _queueNavigationSave() {
    if (state.isResetting) return;
    final store = _store;
    final navigation = LibraryNavigation(
      selectedSourceId: state.selectedSourceId,
      selectedGroup: state.selectedGroup,
      lastChannel: state.lastChannelIdentity,
    );
    _navigationWrites = _navigationWrites
        .then((_) => store.saveNavigation(navigation))
        .onError((error, stackTrace) {
          if (_disposed) return;
          state = state.copyWith(
            error: const SensitiveDataRedactor().text(error.toString()),
            clearMessage: true,
          );
        });
  }

  bool _isValidHttpShape(Uri uri) {
    try {
      const NetworkPolicy().validateHttpUriShape(uri);
      return true;
    } on Object {
      return false;
    }
  }

  static int _compareSources(LibrarySource left, LibrarySource right) {
    final byName = left.name.toLowerCase().compareTo(right.name.toLowerCase());
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }
}

typedef _GuideRefresh = ({
  Map<ChannelIdentity, ChannelSchedule>? schedules,
  String? error,
  bool truncated,
});
