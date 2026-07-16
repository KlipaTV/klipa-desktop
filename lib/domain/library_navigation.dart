import 'channel_identity.dart';

class LibraryNavigation {
  const LibraryNavigation({
    this.selectedSourceId,
    this.selectedGroup,
    this.lastChannel,
  });

  const LibraryNavigation.empty()
    : selectedSourceId = null,
      selectedGroup = null,
      lastChannel = null;

  final String? selectedSourceId;
  final String? selectedGroup;
  final ChannelIdentity? lastChannel;
}
