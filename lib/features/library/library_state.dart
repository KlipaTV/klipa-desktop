import '../../domain/channel.dart';
import '../../domain/channel_identity.dart';
import '../../domain/channel_schedule.dart';
import '../../domain/library_source.dart';

class LibraryState {
  const LibraryState({
    this.sources = const [],
    this.channels = const [],
    this.favoriteChannels = const {},
    this.schedules = const {},
    this.groups = const [],
    this.selectedChannel,
    this.lastChannelIdentity,
    this.selectedSourceId,
    this.selectedGroup,
    this.query = '',
    this.favoritesOnly = false,
    this.isLoading = false,
    this.isImporting = false,
    this.isResetting = false,
    this.operationMessage,
    this.recoveryRequired = false,
    this.message,
    this.error,
  });

  final List<LibrarySource> sources;
  final List<Channel> channels;
  final Set<ChannelIdentity> favoriteChannels;
  final Map<ChannelIdentity, ChannelSchedule> schedules;
  final List<String> groups;
  final Channel? selectedChannel;
  final ChannelIdentity? lastChannelIdentity;
  final String? selectedSourceId;
  final String? selectedGroup;
  final String query;
  final bool favoritesOnly;
  final bool isLoading;
  final bool isImporting;
  final bool isResetting;
  final String? operationMessage;
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

  List<Channel> get sourceChannels => selectedSourceId == null
      ? channels
      : channels
            .where((channel) => channel.sourceId == selectedSourceId)
            .toList(growable: false);

  List<String> get availableGroups => deriveGroups(sourceChannels);

  bool isFavorite(Channel channel) => favoriteChannels.contains((
    sourceId: channel.sourceId,
    channelId: channel.id,
  ));

  ChannelSchedule? scheduleFor(Channel channel) =>
      schedules[(sourceId: channel.sourceId, channelId: channel.id)];

  Channel? get resumeChannel {
    final identity = lastChannelIdentity;
    if (identity == null) return null;
    return channels
        .where(
          (channel) =>
              channel.sourceId == identity.sourceId &&
              channel.id == identity.channelId,
        )
        .firstOrNull;
  }

  List<Channel> get visibleChannels {
    final normalized = query.trim().toLowerCase();
    return sourceChannels
        .where((channel) {
          if (selectedGroup != null && channel.group != selectedGroup) {
            return false;
          }
          if (favoritesOnly && !isFavorite(channel)) return false;
          return normalized.isEmpty ||
              channel.name.toLowerCase().contains(normalized) ||
              (channel.group?.toLowerCase().contains(normalized) ?? false);
        })
        .toList(growable: false);
  }

  LibraryState copyWith({
    List<LibrarySource>? sources,
    List<Channel>? channels,
    Set<ChannelIdentity>? favoriteChannels,
    Map<ChannelIdentity, ChannelSchedule>? schedules,
    List<String>? groups,
    Channel? selectedChannel,
    bool clearSelection = false,
    ChannelIdentity? lastChannelIdentity,
    bool clearLastChannel = false,
    String? selectedSourceId,
    bool clearSource = false,
    String? selectedGroup,
    bool clearGroup = false,
    String? query,
    bool? favoritesOnly,
    bool? isLoading,
    bool? isImporting,
    bool? isResetting,
    String? operationMessage,
    bool clearOperationMessage = false,
    bool? recoveryRequired,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) => LibraryState(
    sources: sources ?? this.sources,
    channels: channels ?? this.channels,
    favoriteChannels: favoriteChannels ?? this.favoriteChannels,
    schedules: schedules ?? this.schedules,
    groups: groups ?? this.groups,
    selectedChannel: clearSelection
        ? null
        : selectedChannel ?? this.selectedChannel,
    lastChannelIdentity: clearLastChannel
        ? null
        : lastChannelIdentity ?? this.lastChannelIdentity,
    selectedSourceId: clearSource
        ? null
        : selectedSourceId ?? this.selectedSourceId,
    selectedGroup: clearGroup ? null : selectedGroup ?? this.selectedGroup,
    query: query ?? this.query,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    isLoading: isLoading ?? this.isLoading,
    isImporting: isImporting ?? this.isImporting,
    isResetting: isResetting ?? this.isResetting,
    operationMessage: clearOperationMessage
        ? null
        : operationMessage ?? this.operationMessage,
    recoveryRequired: recoveryRequired ?? this.recoveryRequired,
    message: clearMessage ? null : message ?? this.message,
    error: clearError ? null : error ?? this.error,
  );
}
