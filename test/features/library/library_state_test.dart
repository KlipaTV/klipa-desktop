import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/features/library/library_state.dart';

void main() {
  test('groups are unique, sorted and combine with search', () {
    final channels = [
      _channel('World News', group: 'News'),
      _channel('Local News', group: 'News'),
      _channel('Football Live', group: 'Sports'),
      _channel('No group'),
    ];
    final state = LibraryState(
      channels: channels,
      groups: LibraryState.deriveGroups(channels),
      selectedGroup: 'News',
      query: 'world',
    );

    expect(state.groups, ['News', 'Sports']);
    expect(state.visibleChannels.map((channel) => channel.name), [
      'World News',
    ]);
  });

  test('a category filter excludes ungrouped and other categories', () {
    final state = LibraryState(
      channels: [
        _channel('News One', group: 'News'),
        _channel('Sports One', group: 'Sports'),
        _channel('No group'),
      ],
      selectedGroup: 'Sports',
    );

    expect(state.visibleChannels.map((channel) => channel.name), [
      'Sports One',
    ]);
  });
}

Channel _channel(String name, {String? group}) => Channel(
  id: name,
  name: name,
  streamUri: Uri.parse('https://stream.example/$name'),
  sourceId: 'fixture',
  allowsPrivateNetwork: false,
  group: group,
);
