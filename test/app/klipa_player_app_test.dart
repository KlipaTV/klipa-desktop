import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/app/klipa_player_app.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/domain/library_source.dart';
import 'package:klipa_player_windows/domain/playlist_source.dart';
import 'package:klipa_player_windows/features/library/library_controller.dart';
import 'package:klipa_player_windows/features/library/library_state.dart';

void main() {
  testWidgets('first run explains content ownership and import choices', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Your channels. Nothing else.'), findsOneWidget);
    expect(find.text('Add playlist URL'), findsOneWidget);
    expect(find.text('Use Xtream login'), findsOneWidget);
    expect(find.text('Open local M3U'), findsOneWidget);
    expect(find.textContaining('does not provide content'), findsOneWidget);
    expect(find.textContaining('No telemetry is sent'), findsOneWidget);
  });

  testWidgets('channel import displays an explicit progress message', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(
            _ImportingFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Signing in and importing channels…'), findsOneWidget);
  });

  testWidgets('success notice counts down for three seconds then disappears', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(_NoticeFixtureController.new),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    expect(find.text('Imported 42 channels.'), findsOneWidget);
    expect(find.byKey(const Key('notice-countdown')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Imported 42 channels.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.text('Imported 42 channels.'), findsNothing);
  });

  testWidgets('full screen hides and restores the library chrome', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const windowChannel = MethodChannel('dev.klipa.player/window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          if (call.method == 'setFullscreen') return call.arguments as bool;
          if (call.method == 'isFullscreen') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(
            _FullscreenFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('source-all')), findsOneWidget);
    expect(
      find.byKey(const Key('open-klipa-website-expanded')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(1000, 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(find.byKey(const Key('source-all')), findsNothing);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('source-all')), findsOneWidget);
  });

  testWidgets(
    'playlist URL dialog requires an explicit private-network opt-in',
    (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-playlist-url')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist-url-field')), findsOneWidget);
      expect(find.byKey(const Key('guide-url-field')), findsOneWidget);
      expect(
        find.text('Allow local/private network addresses'),
        findsOneWidget,
      );
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);
      expect(
        find.textContaining('does not proxy or validate every nested'),
        findsOneWidget,
      );
    },
  );

  testWidgets('local playlist import explains the network trust boundary', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-local-playlist')));
    await tester.pumpAndSettle();

    expect(find.text('Open trusted playlist?'), findsOneWidget);
    expect(
      find.textContaining('does not proxy or validate every nested'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('confirm-local-playlist')), findsOneWidget);
  });

  testWidgets('Xtream login keeps credentials in separate secure fields', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-xtream-login')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('xtream-server-field')), findsOneWidget);
    expect(find.byKey(const Key('xtream-username-field')), findsOneWidget);
    final password = tester.widget<TextField>(
      find.byKey(const Key('xtream-password-field')),
    );
    expect(password.obscureText, isTrue);
    expect(password.autocorrect, isFalse);
    expect(password.enableSuggestions, isFalse);
    expect(find.textContaining('HTTP exposes the login'), findsOneWidget);
    expect(
      find.textContaining('does not proxy or validate every nested'),
      findsOneWidget,
    );
  });

  testWidgets('category filter narrows the visible channel list', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
          libraryControllerProvider.overrideWith(
            _CategoryFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    expect(find.text('News One'), findsOneWidget);
    expect(find.text('Sports One'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sports').last);
    await tester.pumpAndSettle();

    expect(find.text('News One'), findsNothing);
    expect(find.text('Sports One'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('favorite toggles and favorites-only filtering compose', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
          libraryControllerProvider.overrideWith(
            _CategoryFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    await tester.tap(find.byKey(const Key('favorite-fixture-News One')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorites-filter')));
    await tester.pumpAndSettle();
    expect(find.text('News One'), findsOneWidget);
    expect(find.text('Sports One'), findsNothing);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favorite-fixture-News One')));
    await tester.pumpAndSettle();
    expect(find.text('No matching channels'), findsOneWidget);
  });

  testWidgets('storage recovery requires an enumerated reset confirmation', (
    tester,
  ) async {
    _RecoveryFixtureController.resetCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(
            _RecoveryFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    await tester.tap(find.byKey(const Key('recover-reset-app-data')));
    await tester.pumpAndSettle();

    expect(find.text('Reset app data?'), findsOneWidget);
    expect(find.textContaining('provider credentials'), findsOneWidget);
    expect(find.textContaining('favorites'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-reset-app-data')));
    await tester.pump();

    expect(_RecoveryFixtureController.resetCalls, 1);
    expect(find.text('App data was reset.'), findsOneWidget);
  });

  testWidgets('source rail filters and confirms destructive deletion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _ManagementFixtureController.deletedSourceId = null;
    _ManagementFixtureController.renamedSource = null;
    _ManagementFixtureController.refreshCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
          libraryControllerProvider.overrideWith(
            _ManagementFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_ManagementFixtureController.refreshCalls, 1);

    await tester.tap(find.byKey(const Key('source-two')));
    await tester.pump();
    expect(find.text('One News'), findsNothing);
    expect(find.text('Two Sports'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage Source two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-name-field')),
      'Renamed two',
    );
    await tester.tap(find.byKey(const Key('confirm-rename-source')));
    await tester.pumpAndSettle();
    expect(_ManagementFixtureController.renamedSource, ('two', 'Renamed two'));
    expect(find.text('Renamed two'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage Renamed two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete source?'), findsOneWidget);
    expect(find.textContaining('saved login'), findsOneWidget);
    expect(find.textContaining('favorites'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-source')));
    await tester.pumpAndSettle();

    expect(_ManagementFixtureController.deletedSourceId, 'two');
    expect(find.text('Two Sports'), findsNothing);
    expect(find.text('One News'), findsOneWidget);
  });

  testWidgets('import shortcuts are inert while an operation runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(
            _ImportingFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Open trusted playlist?'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const Key('playlist-url-field')), findsNothing);
  });

  testWidgets('the operation overlay blocks pointer input', (tester) async {
    _BlockedImportFixtureController.selectCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
          libraryControllerProvider.overrideWith(
            _BlockedImportFixtureController.new,
          ),
        ],
        child: const KlipaPlayerApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Importing channels…'), findsOneWidget);
    await tester.tap(find.text('News One'), warnIfMissed: false);
    await tester.pump();

    expect(_BlockedImportFixtureController.selectCount, 0);
  });
}

Widget _testApp() => ProviderScope(
  overrides: [
    libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
  ],
  child: const KlipaPlayerApp(),
);

final class _CategoryFixtureController extends LibraryController {
  @override
  LibraryState build() => LibraryState(
    channels: [_channel('News One', 'News'), _channel('Sports One', 'Sports')],
    groups: const ['News', 'Sports'],
  );
}

final class _ImportingFixtureController extends LibraryController {
  @override
  LibraryState build() => LibraryState(
    isImporting: true,
    operationMessage: 'Signing in and importing channels…',
  );
}

final class _BlockedImportFixtureController extends LibraryController {
  static var selectCount = 0;

  @override
  LibraryState build() => LibraryState(
    channels: [_channel('News One', 'News'), _channel('Sports One', 'Sports')],
    groups: const ['News', 'Sports'],
    isImporting: true,
    operationMessage: 'Importing channels…',
  );

  @override
  void select(Channel channel) {
    selectCount++;
  }
}

final class _NoticeFixtureController extends LibraryController {
  @override
  LibraryState build() => LibraryState(message: 'Imported 42 channels.');
}

final class _FullscreenFixtureController extends LibraryController {
  @override
  LibraryState build() {
    final channel = Channel(
      id: 'fullscreen',
      name: 'Fullscreen fixture',
      streamUri: Uri.parse('http://127.0.0.1/stream'),
      sourceId: 'fixture',
      allowsPrivateNetwork: false,
    );
    return LibraryState(
      sources: [_librarySource('fixture')],
      channels: [channel],
      selectedChannel: channel,
    );
  }
}

final class _RecoveryFixtureController extends LibraryController {
  static var resetCalls = 0;

  @override
  LibraryState build() => LibraryState(
    error: 'The encrypted library key is missing.',
    recoveryRequired: true,
  );

  @override
  Future<void> resetLibrary() async {
    resetCalls++;
    state = LibraryState(message: 'App data was reset.');
  }
}

final class _ManagementFixtureController extends LibraryController {
  static String? deletedSourceId;
  static (String, String)? renamedSource;
  static var refreshCalls = 0;

  @override
  LibraryState build() => LibraryState(
    sources: [_librarySource('one'), _librarySource('two')],
    channels: [
      _sourceChannel('One News', 'one', 'News'),
      _sourceChannel('Two Sports', 'two', 'Sports'),
    ],
  );

  @override
  Future<void> deleteSource(String sourceId) async {
    deletedSourceId = sourceId;
    final channels = state.channels
        .where((channel) => channel.sourceId != sourceId)
        .toList(growable: false);
    state = state.copyWith(
      sources: state.sources
          .where((source) => source.id != sourceId)
          .toList(growable: false),
      channels: channels,
      clearSource: state.selectedSourceId == sourceId,
      clearGroup: true,
    );
  }

  @override
  Future<void> refreshActiveSource() async => refreshCalls++;

  @override
  Future<void> renameSource(String sourceId, String name) async {
    renamedSource = (sourceId, name);
    state = state.copyWith(
      sources: [
        for (final source in state.sources)
          source.id == sourceId ? source.copyWith(name: name) : source,
      ],
    );
  }
}

Channel _channel(String name, String group) => Channel(
  id: name,
  name: name,
  streamUri: Uri.parse('https://stream.example/$name'),
  sourceId: 'fixture',
  allowsPrivateNetwork: false,
  group: group,
);

LibrarySource _librarySource(String id) => LibrarySource(
  id: id,
  name: 'Source $id',
  kind: PlaylistSourceKind.remoteUrl,
  allowsPrivateNetwork: false,
  importedAt: DateTime.utc(2026, 7, 15),
  refreshedAt: DateTime.utc(2026, 7, 15),
);

Channel _sourceChannel(String name, String sourceId, String group) => Channel(
  id: name,
  name: name,
  streamUri: Uri.parse('https://stream.example/$name'),
  sourceId: sourceId,
  allowsPrivateNetwork: false,
  group: group,
);
