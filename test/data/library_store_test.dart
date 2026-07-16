import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/security/secret_protector.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/library_navigation.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'klipa-library-store-test-',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('restores a saved source and channel through a fresh store', () async {
    const locationSecret = 'KLIPA_LOCATION_SECRET_71ab';
    const usernameSecret = 'KLIPA_USERNAME_SECRET_82bc';
    const passwordSecret = 'KLIPA_PASSWORD_SECRET_93cd';
    const streamSecret = 'KLIPA_STREAM_SECRET_a4de';
    const headerSecret = 'KLIPA_HEADER_SECRET_b5ef';
    final firstStore = _store(temporaryDirectory);

    await firstStore.replaceSourceSnapshot(
      source: _source(location: 'https://provider.invalid/$locationSecret'),
      channels: [
        _channel(
          streamUri: Uri.parse('https://provider.invalid/$streamSecret'),
          headers: const {'Origin': headerSecret},
        ),
      ],
      username: usernameSecret,
      password: passwordSecret,
    );

    final restored = await _store(temporaryDirectory).load();

    expect(restored.sources.single.name, 'Provider');
    final refreshAccess = await _store(
      temporaryDirectory,
    ).readSourceRefreshAccess('source-1');
    expect(refreshAccess?.source.location, contains(locationSecret));
    expect(restored.channels.single.streamUri.path, contains(streamSecret));
    expect(restored.channels.single.httpHeaders['Origin'], headerSecret);

    final secretValues = [
      locationSecret,
      usernameSecret,
      passwordSecret,
      streamSecret,
      headerSecret,
    ];
    for (final entity in await temporaryDirectory.list().toList()) {
      if (entity is! File) continue;
      final text = utf8.decode(
        await entity.readAsBytes(),
        allowMalformed: true,
      );
      for (final secret in secretValues) {
        expect(text, isNot(contains(secret)), reason: entity.path);
      }
    }
  });

  test('an empty profile does not create storage during startup', () async {
    final snapshot = await _store(temporaryDirectory).load();

    expect(snapshot.sources, isEmpty);
    expect(snapshot.channels, isEmpty);
    expect(await temporaryDirectory.list().toList(), isEmpty);
  });

  test('favorite toggles persist without exposing channel secrets', () async {
    final store = _store(temporaryDirectory);
    await store.replaceSourceSnapshot(
      source: _source(location: 'https://provider.invalid/list'),
      channels: [
        _channel(streamUri: Uri.parse('https://stream.invalid/private-live')),
      ],
    );

    await store.setFavorite(
      sourceId: 'source-1',
      channelId: 'channel-1',
      favorite: true,
    );

    var restored = await _store(temporaryDirectory).load();
    expect(restored.favoriteChannels, {
      (sourceId: 'source-1', channelId: 'channel-1'),
    });

    await store.setFavorite(
      sourceId: 'source-1',
      channelId: 'channel-1',
      favorite: false,
    );
    restored = await _store(temporaryDirectory).load();
    expect(restored.favoriteChannels, isEmpty);
  });

  test(
    'restores only valid library navigation without autoplay state',
    () async {
      final store = _store(temporaryDirectory);
      await store.replaceSourceSnapshot(
        source: _source(location: 'https://provider.invalid/list'),
        channels: [
          _channel(streamUri: Uri.parse('https://stream.invalid/live')),
        ],
      );
      await store.saveNavigation(
        const LibraryNavigation(
          selectedSourceId: 'source-1',
          selectedGroup: 'News',
          lastChannel: (sourceId: 'source-1', channelId: 'channel-1'),
        ),
      );

      var restored = await _store(temporaryDirectory).load();
      expect(restored.navigation.selectedSourceId, 'source-1');
      expect(restored.navigation.selectedGroup, 'News');
      expect(restored.navigation.lastChannel, (
        sourceId: 'source-1',
        channelId: 'channel-1',
      ));

      await store.saveNavigation(
        const LibraryNavigation(
          selectedSourceId: 'missing-source',
          selectedGroup: 'News',
          lastChannel: (
            sourceId: 'missing-source',
            channelId: 'missing-channel',
          ),
        ),
      );
      restored = await _store(temporaryDirectory).load();
      expect(restored.navigation.selectedSourceId, isNull);
      expect(restored.navigation.selectedGroup, isNull);
      expect(restored.navigation.lastChannel, isNull);
    },
  );

  test('reset deletes the database, sidecars, key, and pending key', () async {
    final store = _store(temporaryDirectory);
    await store.replaceSourceSnapshot(
      source: _source(location: 'https://provider.invalid/list'),
      channels: [_channel(streamUri: Uri.parse('https://stream.invalid/live'))],
    );
    await File(
      '${temporaryDirectory.path}/library.key.new',
    ).writeAsBytes([1, 2, 3]);

    await store.reset();

    expect(await temporaryDirectory.list().toList(), isEmpty);
    expect((await store.load()).channels, isEmpty);
  });

  test(
    'rename keeps secrets isolated and delete cascades the source',
    () async {
      final store = _store(temporaryDirectory);
      await store.replaceSourceSnapshot(
        source: _source(location: 'https://provider.invalid/private-location'),
        channels: [
          _channel(streamUri: Uri.parse('https://stream.invalid/private-live')),
        ],
        username: 'private-user',
        password: 'private-password',
      );

      await store.renameSource(sourceId: 'source-1', name: 'Renamed source');

      final renamed = await store.load();
      expect(renamed.sources.single.name, 'Renamed source');
      expect(renamed.sources.single.toString(), isNot(contains('private')));
      final access = await store.readSourceRefreshAccess('source-1');
      expect(access?.source.location, contains('private-location'));
      expect(access?.username, 'private-user');
      expect(access?.password, 'private-password');

      await store.deleteSource('source-1');

      final deleted = await store.load();
      expect(deleted.sources, isEmpty);
      expect(deleted.channels, isEmpty);
      expect(deleted.favoriteChannels, isEmpty);
      expect(await store.readSourceRefreshAccess('source-1'), isNull);
    },
  );

  test(
    'the production store seals its key with Windows DPAPI',
    () async {
      final store = EncryptedLibraryStore(
        rootDirectory: () async => temporaryDirectory,
      );
      await store.replaceSourceSnapshot(
        source: _source(location: 'https://provider.invalid/list'),
        channels: [
          _channel(streamUri: Uri.parse('https://stream.invalid/live')),
        ],
      );

      final restored = await EncryptedLibraryStore(
        rootDirectory: () async => temporaryDirectory,
      ).load();

      expect(restored.sources.single.id, 'source-1');
      expect(restored.channels.single.id, 'channel-1');
    },
    skip: !Platform.isWindows ? 'DPAPI is a Windows-only API.' : false,
  );
}

EncryptedLibraryStore _store(Directory directory) => EncryptedLibraryStore(
  rootDirectory: () async => directory,
  protector: const _TestProtector(),
);

PlaylistSource _source({required String location}) => PlaylistSource(
  id: 'source-1',
  name: 'Provider',
  kind: PlaylistSourceKind.xtream,
  location: location,
  allowsPrivateNetwork: false,
  importedAt: DateTime.utc(2026, 7, 15),
);

Channel _channel({
  required Uri streamUri,
  Map<String, String> headers = const {},
}) => Channel(
  id: 'channel-1',
  name: 'News',
  streamUri: streamUri,
  sourceId: 'source-1',
  allowsPrivateNetwork: false,
  group: 'News',
  httpHeaders: headers,
);

final class _TestProtector implements SecretProtector {
  const _TestProtector();

  @override
  Uint8List protect(Uint8List clearText) => _xor(clearText);

  @override
  Uint8List unprotect(Uint8List protectedData) => _xor(protectedData);

  Uint8List _xor(Uint8List value) => Uint8List.fromList(
    value.map((byte) => byte ^ 0x5a).toList(growable: false),
  );
}
