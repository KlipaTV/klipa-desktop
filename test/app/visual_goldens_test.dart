import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/app/klipa_player_app.dart';
import 'package:klipa_player_windows/data/library_store.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/features/library/library_controller.dart';
import 'package:klipa_player_windows/features/library/library_state.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('onboarding 1440x900', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStoreProvider.overrideWithValue(const DisabledLibraryStore()),
        ],
        child: const KlipaPlayerApp(),
      ),
    );
    await _settleAssets(tester);

    await expectLater(
      find.byType(KlipaPlayerApp),
      matchesGoldenFile(
        'goldens/onboarding_1440x900_${Platform.operatingSystem}.png',
      ),
    );
  });

  testWidgets('library shell 1440x900', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryControllerProvider.overrideWith(_FixtureLibraryController.new),
        ],
        child: const KlipaPlayerApp(),
      ),
    );
    await _settleAssets(tester);

    await expectLater(
      find.byType(KlipaPlayerApp),
      matchesGoldenFile(
        'goldens/library_1440x900_${Platform.operatingSystem}.png',
      ),
    );
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settleAssets(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/logo_mark.png'),
      tester.element(find.byType(Scaffold)),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FixtureLibraryController extends LibraryController {
  @override
  LibraryState build() => LibraryState(
    groups: const ['Entertainment', 'News'],
    channels: List.generate(
      18,
      (index) => Channel(
        id: 'channel-$index',
        name: switch (index) {
          0 => 'Klipa News',
          1 => 'World Report',
          2 => 'City Live',
          _ => 'Sample Channel ${index + 1}',
        },
        streamUri: Uri.parse('https://stream.example/$index'),
        sourceId: 'fixture',
        allowsPrivateNetwork: false,
        group: index < 6 ? 'News' : 'Entertainment',
      ),
    ),
  );
}
