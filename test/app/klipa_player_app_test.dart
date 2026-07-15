import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/app/klipa_player_app.dart';

void main() {
  testWidgets('first run explains content ownership and import choices', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KlipaPlayerApp()));

    expect(find.text('Your channels. Nothing else.'), findsOneWidget);
    expect(find.text('Add playlist URL'), findsOneWidget);
    expect(find.text('Use Xtream login'), findsOneWidget);
    expect(find.text('Open local M3U'), findsOneWidget);
    expect(find.textContaining('does not provide content'), findsOneWidget);
    expect(find.textContaining('sends no telemetry'), findsOneWidget);
  });

  testWidgets(
    'playlist URL dialog requires an explicit private-network opt-in',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: KlipaPlayerApp()));
      await tester.tap(find.byKey(const Key('add-playlist-url')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist-url-field')), findsOneWidget);
      expect(
        find.text('Allow local/private network addresses'),
        findsOneWidget,
      );
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);
    },
  );

  testWidgets('Xtream login keeps credentials in separate secure fields', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KlipaPlayerApp()));
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
  });
}
