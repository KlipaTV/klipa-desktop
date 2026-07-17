import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/features/player/player_pane.dart';
import 'package:klipa_player_windows/platform/app_window_controller.dart';

void main() {
  testWidgets('mute shortcut is scoped to a focused player', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: PlayerPane(channel: _blockedFixtureChannel())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tapAt(const Offset(400, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    expect(find.byTooltip('Unmute'), findsOneWidget);
  });

  testWidgets('single-letter shortcuts do not capture text-field focus', (
    tester,
  ) async {
    final textFocus = FocusNode();
    addTearDown(textFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: textFocus),
              Expanded(child: PlayerPane(channel: _blockedFixtureChannel())),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    textFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsNothing);
  });

  testWidgets('F and Escape enter and exit full screen with player focus', (
    tester,
  ) async {
    final windowController = _FakeWindowController();
    final fullscreenChanges = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PlayerPane(
            channel: _blockedFixtureChannel(),
            windowController: windowController,
            onFullscreenChanged: fullscreenChanges.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(windowController.requests, [true]);
    expect(fullscreenChanges, [true]);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(windowController.requests, [true, false]);
    expect(fullscreenChanges, [true, false]);
    expect(find.byTooltip('Enter full screen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(windowController.requests, [true, false, true]);
    expect(fullscreenChanges, [true, false, true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(windowController.requests, [true, false, true, false]);
  });

  testWidgets('escape exits full screen after the channel is cleared', (
    tester,
  ) async {
    final windowController = _FakeWindowController();
    final fullscreenChanges = <bool>[];
    late StateSetter setChannel;
    Channel? active = _blockedFixtureChannel();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setChannel = setState;
              return PlayerPane(
                channel: active,
                windowController: windowController,
                onFullscreenChanged: fullscreenChanges.add,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(windowController.requests, [true]);

    setChannel(() => active = null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Choose a channel'), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(windowController.requests, [true, false]);
    expect(fullscreenChanges, [true, false]);
  });
}

Channel _blockedFixtureChannel() => Channel(
  id: 'blocked-fixture',
  name: 'Blocked fixture',
  streamUri: Uri.parse('http://127.0.0.1/stream'),
  sourceId: 'fixture',
  allowsPrivateNetwork: false,
);

final class _FakeWindowController implements AppWindowController {
  final requests = <bool>[];

  @override
  Future<bool> isFullscreen() async => requests.lastOrNull ?? false;

  @override
  Future<bool> setFullscreen(bool enabled) async {
    requests.add(enabled);
    return enabled;
  }
}
