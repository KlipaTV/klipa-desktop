import '../../domain/channel.dart';
import '../../domain/playlist_source.dart';

class LibraryState {
  const LibraryState({
    this.sources = const [],
    this.channels = const [],
    this.groups = const [],
    this.selectedChannel,
    this.selectedGroup,
    this.query = '',
    this.isLoading = false,
    this.isImporting = false,
    this.isResetting = false,
    this.recoveryRequired = false,
    this.message,
    this.error,
  });

  final List<PlaylistSource> sources;
  final List<Channel> channels;
  final List<String> groups;
  final Channel? selectedChannel;
  final String? selectedGroup;
  final String query;
  final bool isLoading;
  final bool isImporting;
  final bool isResetting;
  final bool recoveryRequired;
  final String? message;
  final String? error;

  static List<String> deriveGroups(Iterable<Channel> channels) {
    final values =
        <String>{
          for (final channel in channels)
            if (channel.group case final group? when group.trim().isNotEmpty)
              group,
        }.toList()..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
    return List.unmodifiable(values);
  }

  List<Channel> get visibleChannels {
    final normalized = query.trim().toLowerCase();
    return channels
        .where((channel) {
          if (selectedGroup != null && channel.group != selectedGroup) {
            return false;
          }
          return normalized.isEmpty ||
              channel.name.toLowerCase().contains(normalized) ||
              (channel.group?.toLowerCase().contains(normalized) ?? false);
        })
        .toList(growable: false);
  }

  LibraryState copyWith({
    List<PlaylistSource>? sources,
    List<Channel>? channels,
    List<String>? groups,
    Channel? selectedChannel,
    bool clearSelection = false,
    String? selectedGroup,
    bool clearGroup = false,
    String? query,
    bool? isLoading,
    bool? isImporting,
    bool? isResetting,
    bool? recoveryRequired,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) => LibraryState(
    sources: sources ?? this.sources,
    channels: channels ?? this.channels,
    groups: groups ?? this.groups,
    selectedChannel: clearSelection
        ? null
        : selectedChannel ?? this.selectedChannel,
    selectedGroup: clearGroup ? null : selectedGroup ?? this.selectedGroup,
    query: query ?? this.query,
    isLoading: isLoading ?? this.isLoading,
    isImporting: isImporting ?? this.isImporting,
    isResetting: isResetting ?? this.isResetting,
    recoveryRequired: recoveryRequired ?? this.recoveryRequired,
    message: clearMessage ? null : message ?? this.message,
    error: clearError ? null : error ?? this.error,
  );
}
