import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/sensitive_data_redactor.dart';
import '../../data/encrypted_library_database.dart';
import '../../data/library_store.dart';
import '../../data/playlist_import_service.dart';
import '../../domain/channel.dart';
import '../../domain/channel_identity.dart';
import '../../domain/library_source.dart';
import 'library_state.dart';

final playlistImportServiceProvider = Provider<PlaylistImportService>(
  (ref) => PlaylistImportService(),
);

final libraryStoreProvider = Provider<LibraryStore>(
  (ref) => Platform.isWindows
      ? EncryptedLibraryStore()
      : const DisabledLibraryStore(),
);

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  var _disposed = false;
  final _favoriteWrites = <ChannelIdentity>{};

  PlaylistImportService get _importer =>
      ref.read(playlistImportServiceProvider);

  LibraryStore get _store => ref.read(libraryStoreProvider);

  @override
  LibraryState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_restoreLibrary));
    return const LibraryState(isLoading: true);
  }

  Future<void> importUrl(
    String value, {
    required bool allowPrivateNetwork,
  }) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      state = state.copyWith(error: 'Enter a valid playlist address.');
      return;
    }
    await _import(
      () => _importer.fromUrl(uri, allowPrivateNetwork: allowPrivateNetwork),
    );
  }

  Future<void> importFile() async {
    await _import(_importer.fromFilePicker);
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
      username: username.trim(),
      password: password,
    );
  }

  void search(String value) {
    state = state.copyWith(query: value);
  }

  void filterGroup(String? value) {
    state = state.copyWith(selectedGroup: value, clearGroup: value == null);
  }

  void filterSource(String? sourceId) {
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
  }

  void setFavoritesOnly(bool value) {
    state = state.copyWith(favoritesOnly: value);
  }

  Future<void> toggleFavorite(Channel channel) async {
    if (_operationInProgress) return;
    final identity = (sourceId: channel.sourceId, channelId: channel.id);
    if (!_favoriteWrites.add(identity)) return;
    final favorite = !state.favoriteChannels.contains(identity);
    try {
      await _store.setFavorite(
        sourceId: identity.sourceId,
        channelId: identity.channelId,
        favorite: favorite,
      );
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
    state = state.copyWith(selectedChannel: channel, clearError: true);
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
    _startOperation();
    try {
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
      );
      if (_disposed) return;
      _publishSourceSnapshot(result, verb: 'Refreshed');
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
    _startOperation();
    try {
      await _store.renameSource(sourceId: sourceId, name: normalized);
      if (_disposed) return;
      state = state.copyWith(
        sources: List.unmodifiable([
          for (final source in state.sources)
            source.id == sourceId ? source.copyWith(name: normalized) : source,
        ]),
        isImporting: false,
        message: 'Renamed source.',
      );
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  Future<void> deleteSource(String sourceId) async {
    if (_operationInProgress) return;
    _startOperation();
    try {
      await _store.deleteSource(sourceId);
      if (_disposed) return;
      final channels = state.channels
          .where((channel) => channel.sourceId != sourceId)
          .toList(growable: false);
      final selectedWasDeleted = state.selectedChannel?.sourceId == sourceId;
      final sourceFilterWasDeleted = state.selectedSourceId == sourceId;
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
        clearSelection: selectedWasDeleted,
        clearSource: sourceFilterWasDeleted,
        clearGroup: sourceFilterWasDeleted,
        isImporting: false,
        message: 'Deleted source.',
      );
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  bool get _operationInProgress =>
      state.isLoading ||
      state.isImporting ||
      state.isResetting ||
      _favoriteWrites.isNotEmpty;

  void _startOperation() {
    state = state.copyWith(
      isImporting: true,
      clearError: true,
      clearMessage: true,
    );
  }

  void _failOperation(Object error) {
    if (_disposed) return;
    state = state.copyWith(
      isImporting: false,
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
      await _store.reset();
      if (_disposed) return;
      state = const LibraryState(message: 'App data was reset.');
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
    String? username,
    String? password,
  }) async {
    if (_operationInProgress) return;
    _startOperation();
    try {
      final result = await operation();
      if (_disposed) return;
      if (result == null) {
        state = state.copyWith(isImporting: false);
        return;
      }

      await _store.replaceSourceSnapshot(
        source: result.source,
        channels: result.channels,
        username: username,
        password: password,
      );
      if (_disposed) return;

      _publishSourceSnapshot(result, verb: 'Imported');
    } on Object catch (error) {
      _failOperation(error);
    }
  }

  void _publishSourceSnapshot(
    PlaylistImportResult result, {
    required String verb,
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
    final sources = <LibrarySource>[
      ...otherSources,
      previousSource == null
          ? source
          : source.copyWith(name: previousSource.name),
    ]..sort((left, right) => left.name.compareTo(right.name));
    state = state.copyWith(
      sources: List.unmodifiable(sources),
      channels: List.unmodifiable(channels),
      favoriteChannels: Set.unmodifiable(favorites),
      groups: LibraryState.deriveGroups(channels),
      selectedChannel: refreshedSelection,
      clearSelection: selectedId != null && refreshedSelection == null,
      clearGroup: !keepSelectedGroup,
      isImporting: false,
      message: '$verb ${result.channels.length} channels.$warningSuffix',
    );
  }

  Future<void> _restoreLibrary() async {
    try {
      final snapshot = await _store.load();
      if (_disposed) return;
      final channels = snapshot.channels.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      state = state.copyWith(
        sources: List.unmodifiable(snapshot.sources),
        channels: List.unmodifiable(channels),
        favoriteChannels: Set.unmodifiable(snapshot.favoriteChannels),
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
}
