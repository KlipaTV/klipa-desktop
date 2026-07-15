import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/sensitive_data_redactor.dart';
import '../../data/library_store.dart';
import '../../data/playlist_import_service.dart';
import '../../domain/channel.dart';
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

  void select(Channel channel) {
    state = state.copyWith(selectedChannel: channel, clearError: true);
  }

  void dismissNotices() {
    state = state.copyWith(clearMessage: true, clearError: true);
  }

  Future<void> resetLibrary() async {
    if (state.isLoading || state.isImporting || state.isResetting) return;
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
    if (state.isLoading || state.isImporting) return;
    state = state.copyWith(
      isImporting: true,
      clearError: true,
      clearMessage: true,
    );
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

      final otherChannels = state.channels
          .where((channel) => channel.sourceId != result.source.id)
          .toList();
      final otherSources = state.sources
          .where((source) => source.id != result.source.id)
          .toList();
      final channels = [...otherChannels, ...result.channels]
        ..sort((left, right) => left.name.compareTo(right.name));
      final keepSelectedGroup =
          state.selectedGroup == null ||
          channels.any((channel) => channel.group == state.selectedGroup);
      final warningSuffix = result.warnings.isEmpty
          ? ''
          : ' ${result.warnings.length} entries were skipped or limited.';
      state = state.copyWith(
        sources: [...otherSources, result.source],
        channels: List.unmodifiable(channels),
        groups: LibraryState.deriveGroups(channels),
        clearGroup: !keepSelectedGroup,
        isImporting: false,
        message: 'Imported ${result.channels.length} channels.$warningSuffix',
      );
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        isImporting: false,
        error: const SensitiveDataRedactor().text(error.toString()),
      );
    }
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
