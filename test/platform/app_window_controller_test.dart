import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/platform/app_window_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.klipa.player/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the private window channel for full-screen state', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'setFullscreen' => call.arguments as bool,
            'isFullscreen' => true,
            _ => null,
          };
        });
    const controller = MethodChannelAppWindowController();

    expect(await controller.setFullscreen(true), isTrue);
    expect(await controller.isFullscreen(), isTrue);
    expect(calls, hasLength(2));
    expect(calls.first.method, 'setFullscreen');
    expect(calls.first.arguments, isTrue);
    expect(calls.last.method, 'isFullscreen');
  });
}
