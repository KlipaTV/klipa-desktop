import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/domain/channel.dart';
import 'package:klipa_player_windows/features/player/player_pane.dart';
import 'package:klipa_player_windows/features/player/video_player_port.dart';

void main() {
  testWidgets('resume waits for an explicit click before opening media', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('resume');
    addTearDown(player.closeStreams);
    final resume = _channel('resume');
    Channel? active;
    var factoryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlayerPane(
              channel: active,
              resumeChannel: resume,
              onResume: () => setState(() => active = resume),
              playerFactory: () {
                factoryCalls++;
                return player;
              },
              channelStartTimeout: const Duration(seconds: 1),
              openCommandTimeout: const Duration(milliseconds: 50),
              readinessGrace: const Duration(milliseconds: 10),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('resume-last-channel')), findsOneWidget);
    expect(factoryCalls, 0);
    expect(player.opened, isEmpty);

    await tester.tap(find.byKey(const Key('resume-last-channel')));
    await _pumpUntil(tester, () => player.opened.isNotEmpty);
    expect(factoryCalls, 1);
    expect(player.opened.single.id, 'resume');
  });

  testWidgets('times out, disposes, and retries a channel start', (
    tester,
  ) async {
    final first = _FakeVideoPlayerPort('first');
    final second = _FakeVideoPlayerPort('second');
    final ports = [first, second];
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => ports[factoryIndex++],
      ),
    );
    await _pumpOpen(tester);
    expect(first.opened.map((channel) => channel.id), ['one']);

    await tester.pump(const Duration(milliseconds: 120));
    await _pumpOpen(tester);

    expect(find.text(_timeoutMessage), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(first.disposeCount, 1);

    await tester.tap(find.text('Try again'));
    await _pumpUntil(tester, () => second.opened.isNotEmpty);
    expect(second.opened.map((channel) => channel.id), ['one']);
    second.emitPlaying(true);
    second.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));

    expect(find.text(_timeoutMessage), findsNothing);
    expect(find.byKey(const ValueKey('fake-video-second')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text(_timeoutMessage), findsNothing);
  });

  testWidgets('a hung native open uses the same retryable timeout', (
    tester,
  ) async {
    final gate = Completer<void>();
    final player = _FakeVideoPlayerPort('hung', openGate: gate);
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      _testApp(
        channel: _channel('hung'),
        playerFactory: () => player,
        openCommandTimeout: const Duration(milliseconds: 25),
        channelStartTimeout: const Duration(seconds: 1),
      ),
    );
    await _pumpOpen(tester);
    await tester.pump(const Duration(milliseconds: 30));
    await _pumpOpen(tester);

    expect(find.text(_timeoutMessage), findsOneWidget);
    expect(player.disposeCount, 1);
    if (!gate.isCompleted) gate.complete();
  });

  testWidgets('rapid replacement rejects stale completion and errors', (
    tester,
  ) async {
    final firstGate = Completer<void>();
    final first = _FakeVideoPlayerPort('first', openGate: firstGate);
    final second = _FakeVideoPlayerPort('second');
    final ports = [first, second];
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;
    VideoPlayerPort factory() {
      if (factoryIndex == 1) {
        expect(first.disposeCount, 1, reason: 'old player must be gone first');
      }
      return ports[factoryIndex++];
    }

    await tester.pumpWidget(
      _testApp(channel: _channel('one'), playerFactory: factory),
    );
    await _pumpOpen(tester);
    expect(first.opened.single.id, 'one');

    await tester.pumpWidget(
      _testApp(channel: _channel('two'), playerFactory: factory),
    );
    firstGate.complete();
    await _pumpUntil(tester, () => second.opened.isNotEmpty);

    expect(first.disposeCount, 1);
    expect(second.opened.single.id, 'two');
    first.emitError(
      'stale https://user:password@example.invalid/private/token',
    );
    second.emitPlaying(true);
    second.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));

    expect(find.text('Channel two'), findsOneWidget);
    expect(find.textContaining('stale'), findsNothing);
    expect(find.byKey(const ValueKey('fake-video-second')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('same channel ID from another source replaces the player', (
    tester,
  ) async {
    final first = _FakeVideoPlayerPort('first-source');
    final second = _FakeVideoPlayerPort('second-source');
    final ports = [first, second];
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('shared', sourceId: 'one'),
        playerFactory: () => ports[factoryIndex++],
      ),
    );
    await _pumpOpen(tester);

    await tester.pumpWidget(
      _testApp(
        channel: _channel('shared', sourceId: 'two'),
        playerFactory: () => ports[factoryIndex++],
      ),
    );
    await _pumpUntil(tester, () => second.opened.isNotEmpty);

    expect(first.disposeCount, 1);
    expect(second.opened.single.sourceId, 'two');
  });

  testWidgets('current playback errors are redacted and retryable', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('error');
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      _testApp(channel: _channel('one'), playerFactory: () => player),
    );
    await _pumpOpen(tester);
    player.emitError(
      'failed https://user:password@example.invalid/private/token?key=secret',
    );
    await tester.pump();
    await _pumpOpen(tester);

    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('password'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(
      find.text(
        'This channel could not be opened. Check the source and try again.',
      ),
      findsOneWidget,
    );
    expect(player.disposeCount, 1);
  });

  testWidgets('an error the picture outlives does not stop the channel', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('no-audio-device');
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => player,
        errorGrace: const Duration(milliseconds: 20),
      ),
    );
    await _pumpOpen(tester);
    // libmpv reports a missing audio output at error level, then keeps
    // playing the picture.
    player.emitError('Could not open/initialize audio device -> no sound.');
    player.emitPlaying(true);
    player.emitBuffering(false);
    player.position = const Duration(seconds: 1);
    await _pumpFor(tester, const Duration(milliseconds: 40));

    expect(find.text('Try again'), findsNothing);
    expect(
      find.byKey(const ValueKey('fake-video-no-audio-device')),
      findsOneWidget,
    );
    expect(player.disposeCount, 0);
  });

  testWidgets('an error playback does not outlive fails after the grace', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('dead');
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => player,
        errorGrace: const Duration(milliseconds: 20),
      ),
    );
    await _pumpOpen(tester);
    player.emitError('tcp: Connection refused');
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Try again'), findsNothing);

    await _pumpFor(tester, const Duration(milliseconds: 20));
    expect(find.text('Try again'), findsOneWidget);
    expect(player.disposeCount, 1);
  });

  testWidgets('a live channel that stops after playing is reopened', (
    tester,
  ) async {
    final first = _FakeVideoPlayerPort('first');
    final second = _FakeVideoPlayerPort('second');
    final ports = [first, second];
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => ports[factoryIndex++],
      ),
    );
    await _pumpOpen(tester);
    first.emitPlaying(true);
    first.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));
    expect(find.text('LIVE'), findsOneWidget);

    first.emitCompleted();
    await tester.pump();
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    await _pumpUntil(tester, () => second.opened.isNotEmpty);
    expect(first.disposeCount, 1);
    expect(second.opened.single.id, 'one');
    second.emitPlaying(true);
    second.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-video-second')), findsOneWidget);
  });

  testWidgets('reopening stops after the configured attempts', (tester) async {
    final ports = List.generate(4, (index) => _FakeVideoPlayerPort('p$index'));
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => ports[factoryIndex++],
        channelStartTimeout: const Duration(milliseconds: 30),
      ),
    );
    await _pumpOpen(tester);
    ports.first.emitPlaying(true);
    ports.first.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));
    ports.first.emitCompleted();

    // Neither reopened player ever starts, so each attempt times out.
    await _pumpFor(tester, const Duration(milliseconds: 200));

    expect(factoryIndex, 3);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.text(
        'The channel stopped and did not come back. You can try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a stream that ends before it ever played is not reopened', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('ended');
    addTearDown(player.closeStreams);
    var factoryCalls = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () {
          factoryCalls++;
          return player;
        },
      ),
    );
    await _pumpOpen(tester);
    player.emitCompleted();
    await _pumpFor(tester, const Duration(milliseconds: 40));

    expect(factoryCalls, 1);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('RECONNECTING'), findsNothing);
  });

  testWidgets('the pointer hides with the controls during playback', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort('cursor');
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => player,
        channelStartTimeout: const Duration(seconds: 10),
      ),
    );
    await _pumpOpen(tester);
    player.emitPlaying(true);
    player.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));
    MouseCursor playerCursor() => tester
        .widgetList<MouseRegion>(
          find.descendant(
            of: find.byType(PlayerPane),
            matching: find.byType(MouseRegion),
          ),
        )
        .first
        .cursor;
    expect(playerCursor(), MouseCursor.defer);

    await tester.pump(const Duration(seconds: 4));
    expect(playerCursor(), SystemMouseCursors.none);
  });

  testWidgets('a failing player teardown does not block later channels', (
    tester,
  ) async {
    final first = _FakeVideoPlayerPort(
      'first',
      disposeError: StateError('native teardown failed'),
    );
    final second = _FakeVideoPlayerPort('second');
    final ports = [first, second];
    addTearDown(() => Future.wait(ports.map((port) => port.closeStreams())));
    var factoryIndex = 0;

    await tester.pumpWidget(
      _testApp(
        channel: _channel('one'),
        playerFactory: () => ports[factoryIndex++],
        channelStartTimeout: const Duration(seconds: 1),
      ),
    );
    await _pumpOpen(tester);
    expect(first.opened.single.id, 'one');

    await tester.pumpWidget(
      _testApp(
        channel: _channel('two'),
        playerFactory: () => ports[factoryIndex++],
        channelStartTimeout: const Duration(seconds: 1),
      ),
    );
    await _pumpUntil(tester, () => second.opened.isNotEmpty);

    expect(first.disposeCount, 1);
    expect(second.opened.single.id, 'two');
    second.emitPlaying(true);
    second.emitBuffering(false);
    await tester.pump(const Duration(milliseconds: 15));

    expect(find.byKey(const ValueKey('fake-video-second')), findsOneWidget);
    expect(find.text(_timeoutMessage), findsNothing);
  });

  testWidgets('external stop completes when player disposal fails', (
    tester,
  ) async {
    final player = _FakeVideoPlayerPort(
      'faulty',
      disposeError: StateError('native teardown failed'),
    );
    final controller = PlayerPaneController();
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPane(
            channel: _channel('one'),
            controller: controller,
            playerFactory: () => player,
            channelStartTimeout: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await _pumpOpen(tester);

    await controller.stop();
    await tester.pump();

    expect(player.disposeCount, 1);
    expect(find.byKey(const ValueKey('fake-video-faulty')), findsNothing);
  });

  testWidgets('external stop awaits native player disposal', (tester) async {
    final player = _FakeVideoPlayerPort('reset');
    final controller = PlayerPaneController();
    addTearDown(player.closeStreams);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPane(
            channel: _channel('one'),
            controller: controller,
            playerFactory: () => player,
            channelStartTimeout: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await _pumpOpen(tester);

    await controller.stop();
    await tester.pump();

    expect(player.disposeCount, 1);
    expect(find.byKey(const ValueKey('fake-video-reset')), findsNothing);
  });
}

const _timeoutMessage = 'The channel did not start in time. You can try again.';

Widget _testApp({
  required Channel channel,
  required VideoPlayerPortFactory playerFactory,
  Duration channelStartTimeout = const Duration(milliseconds: 100),
  Duration openCommandTimeout = const Duration(milliseconds: 50),
  Duration errorGrace = Duration.zero,
  Duration reconnectDelay = const Duration(milliseconds: 10),
  int maxReconnectAttempts = 2,
}) => MaterialApp(
  theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
  home: Scaffold(
    body: PlayerPane(
      channel: channel,
      playerFactory: playerFactory,
      channelStartTimeout: channelStartTimeout,
      openCommandTimeout: openCommandTimeout,
      readinessGrace: const Duration(milliseconds: 10),
      errorGrace: errorGrace,
      reconnectDelay: reconnectDelay,
      maxReconnectAttempts: maxReconnectAttempts,
    ),
  ),
);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 5);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
    await tester.pump(step);
  }
}

Future<void> _pumpOpen(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 50 && !condition(); index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    condition(),
    isTrue,
    reason: 'asynchronous player work did not finish',
  );
}

Channel _channel(String id, {String sourceId = 'fixture'}) => Channel(
  id: id,
  name: 'Channel $id',
  streamUri: Uri.parse('https://1.1.1.1/$id'),
  sourceId: sourceId,
  allowsPrivateNetwork: false,
);

final class _FakeVideoPlayerPort implements VideoPlayerPort {
  _FakeVideoPlayerPort(this.label, {this.openGate, this.disposeError});

  final String label;
  final Completer<void>? openGate;
  final Error? disposeError;
  final opened = <Channel>[];
  final _errors = StreamController<String>.broadcast(sync: true);
  final _playingChanges = StreamController<bool>.broadcast(sync: true);
  final _bufferingChanges = StreamController<bool>.broadcast(sync: true);
  final _completedChanges = StreamController<bool>.broadcast(sync: true);
  var _playing = false;
  var _buffering = true;
  var disposeCount = 0;
  var playOrPauseCount = 0;
  double volume = 100;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Stream<bool> get bufferingChanges => _bufferingChanges.stream;

  @override
  Stream<bool> get completedChanges => _completedChanges.stream;

  @override
  bool get playing => _playing;

  @override
  Duration position = Duration.zero;

  @override
  bool get buffering => _buffering;

  @override
  Widget buildView({required BoxFit fit}) =>
      ColoredBox(key: ValueKey('fake-video-$label'), color: Colors.black);

  @override
  Future<void> open(Channel channel) async {
    opened.add(channel);
    await openGate?.future;
  }

  @override
  Future<void> playOrPause() async => playOrPauseCount++;

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (disposeError case final error?) throw error;
  }

  void emitPlaying(bool value) {
    _playing = value;
    _playingChanges.add(value);
  }

  void emitBuffering(bool value) {
    _buffering = value;
    _bufferingChanges.add(value);
  }

  void emitError(String value) => _errors.add(value);

  void emitCompleted() {
    _playing = false;
    _completedChanges.add(true);
  }

  Future<void> closeStreams() async {
    await _errors.close();
    await _playingChanges.close();
    await _bufferingChanges.close();
    await _completedChanges.close();
  }
}
