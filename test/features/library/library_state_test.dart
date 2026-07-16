import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/library_source.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
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

  test('source filtering derives only relevant groups and channels', () {
    final state = LibraryState(
      sources: [_source('one'), _source('two')],
      channels: [
        _channelForSource('One News', 'one', group: 'News'),
        _channelForSource('Two Sports', 'two', group: 'Sports'),
      ],
      selectedSourceId: 'two',
    );

    expect(state.availableGroups, ['Sports']);
    expect(state.visibleChannels.map((channel) => channel.name), [
      'Two Sports',
    ]);
  });

  test('favorites combine with source, category, and search filters', () {
    final favorite = _channelForSource('One News', 'one', group: 'News');
    final state = LibraryState(
      channels: [
        favorite,
        _channelForSource('One Sports', 'one', group: 'Sports'),
        _channelForSource('Two News', 'two', group: 'News'),
      ],
      favoriteChannels: const {
        (sourceId: 'one', channelId: 'One News'),
        (sourceId: 'two', channelId: 'Two News'),
      },
      selectedSourceId: 'one',
      selectedGroup: 'News',
      query: 'one',
      favoritesOnly: true,
    );

    expect(state.isFavorite(favorite), isTrue);
    expect(state.visibleChannels, [favorite]);
  });

  test('resume channel resolves only an exact source and channel identity', () {
    final channel = _channelForSource('News', 'one');
    expect(
      LibraryState(
        channels: [channel],
        lastChannelIdentity: const (sourceId: 'one', channelId: 'News'),
      ).resumeChannel,
      channel,
    );
    expect(
      LibraryState(
        channels: [channel],
        lastChannelIdentity: const (sourceId: 'two', channelId: 'News'),
      ).resumeChannel,
      isNull,
    );
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

Channel _channelForSource(String name, String sourceId, {String? group}) =>
    Channel(
      id: name,
      name: name,
      streamUri: Uri.parse('https://stream.example/$name'),
      sourceId: sourceId,
      allowsPrivateNetwork: false,
      group: group,
    );

LibrarySource _source(String id) => LibrarySource(
  id: id,
  name: 'Source $id',
  kind: PlaylistSourceKind.remoteUrl,
  allowsPrivateNetwork: false,
  importedAt: DateTime.utc(2026, 7, 15),
  refreshedAt: DateTime.utc(2026, 7, 15),
);
