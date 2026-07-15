import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/sensitive_data_redactor.dart';
import '../../data/playlist_import_service.dart';
import '../../domain/channel.dart';
import 'library_state.dart';

final playlistImportServiceProvider = Provider<PlaylistImportService>(
  (ref) => PlaylistImportService(),
);

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  PlaylistImportService get _importer =>
      ref.read(playlistImportServiceProvider);

  @override
  LibraryState build() => const LibraryState();

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

  Future<void> _import(
    Future<PlaylistImportResult?> Function() operation,
  ) async {
    if (state.isImporting) return;
    state = state.copyWith(
      isImporting: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await operation();
      if (result == null) {
        state = state.copyWith(isImporting: false);
        return;
      }

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
      state = state.copyWith(
        isImporting: false,
        error: const SensitiveDataRedactor().text(error.toString()),
      );
    }
  }
}
