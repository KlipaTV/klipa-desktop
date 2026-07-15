import '../../domain/channel.dart';
import '../../domain/playlist_source.dart';

class LibraryState {
  const LibraryState({
    this.sources = const [],
    this.channels = const [],
    this.selectedChannel,
    this.query = '',
    this.isImporting = false,
    this.message,
    this.error,
  });

  final List<PlaylistSource> sources;
  final List<Channel> channels;
  final Channel? selectedChannel;
  final String query;
  final bool isImporting;
  final String? message;
  final String? error;

  List<Channel> get visibleChannels {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return channels;
    return channels
        .where(
          (channel) =>
              channel.name.toLowerCase().contains(normalized) ||
              (channel.group?.toLowerCase().contains(normalized) ?? false),
        )
        .toList(growable: false);
  }

  LibraryState copyWith({
    List<PlaylistSource>? sources,
    List<Channel>? channels,
    Channel? selectedChannel,
    bool clearSelection = false,
    String? query,
    bool? isImporting,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) => LibraryState(
    sources: sources ?? this.sources,
    channels: channels ?? this.channels,
    selectedChannel: clearSelection
        ? null
        : selectedChannel ?? this.selectedChannel,
    query: query ?? this.query,
    isImporting: isImporting ?? this.isImporting,
    message: clearMessage ? null : message ?? this.message,
    error: clearError ? null : error ?? this.error,
  );
}
