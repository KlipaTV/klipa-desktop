import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/features/player/playback_control_bar.dart';

void main() {
  test('only hides controls during uninterrupted playback', () {
    expect(
      shouldShowPlaybackControls(
        requestedVisible: false,
        playing: true,
        buffering: false,
        opening: false,
        hasError: false,
      ),
      isFalse,
    );
    for (final state in [
      (playing: false, buffering: false, opening: false, hasError: false),
      (playing: true, buffering: true, opening: false, hasError: false),
      (playing: true, buffering: false, opening: true, hasError: false),
      (playing: true, buffering: false, opening: false, hasError: true),
    ]) {
      expect(
        shouldShowPlaybackControls(
          requestedVisible: false,
          playing: state.playing,
          buffering: state.buffering,
          opening: state.opening,
          hasError: state.hasError,
        ),
        isTrue,
      );
    }
  });

  testWidgets('exposes compact live playback controls', (tester) async {
    var playPauseCount = 0;
    var muteCount = 0;
    var fitCount = 0;
    var fullscreenCount = 0;
    double? changedVolume;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlaybackControlBar(
            channelName: 'Klipa News',
            playing: true,
            buffering: false,
            muted: false,
            volume: 65,
            fit: BoxFit.contain,
            fullscreen: false,
            onPlayPause: () => playPauseCount++,
            onMute: () => muteCount++,
            onVolumeChanged: (value) => changedVolume = value,
            onFitChanged: () => fitCount++,
            onFullscreenChanged: () => fullscreenCount++,
          ),
        ),
      ),
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Klipa News'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Fill video'), findsOneWidget);
    expect(find.byTooltip('Enter full screen'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Fill video'));
    await tester.tap(find.byTooltip('Enter full screen'));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(35);

    expect(playPauseCount, 1);
    expect(muteCount, 1);
    expect(fitCount, 1);
    expect(fullscreenCount, 1);
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
            buffering: true,
            muted: true,
            volume: 0,
            fit: BoxFit.cover,
            fullscreen: true,
            onPlayPause: () {},
            onMute: () {},
            onVolumeChanged: (_) {},
            onFitChanged: () {},
            onFullscreenChanged: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('BUFFERING'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byTooltip('Fit video'), findsOneWidget);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });
}
