import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/features/player/playback_control_bar.dart';

void main() {
  testWidgets('exposes compact live playback controls', (tester) async {
    var playPauseCount = 0;
    var muteCount = 0;
    var fitCount = 0;
    double? changedVolume;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlaybackControlBar(
            channelName: 'Klipa News',
            playing: true,
            muted: false,
            volume: 65,
            fit: BoxFit.contain,
            onPlayPause: () => playPauseCount++,
            onMute: () => muteCount++,
            onVolumeChanged: (value) => changedVolume = value,
            onFitChanged: () => fitCount++,
          ),
        ),
      ),
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Klipa News'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Fill video'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Fill video'));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(35);

    expect(playPauseCount, 1);
    expect(muteCount, 1);
    expect(fitCount, 1);
    expect(changedVolume, 35);
  });

  testWidgets('shows muted and fill-mode affordances', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlaybackControlBar(
            channelName: 'Test channel',
            playing: false,
            muted: true,
            volume: 0,
            fit: BoxFit.cover,
            onPlayPause: () {},
            onMute: () {},
            onVolumeChanged: (_) {},
            onFitChanged: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byTooltip('Fit video'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });
}
