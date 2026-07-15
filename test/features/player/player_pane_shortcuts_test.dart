import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/features/player/player_pane.dart';

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
}

Channel _blockedFixtureChannel() => Channel(
  id: 'blocked-fixture',
  name: 'Blocked fixture',
  streamUri: Uri.parse('http://127.0.0.1/stream'),
  sourceId: 'fixture',
  allowsPrivateNetwork: false,
);
