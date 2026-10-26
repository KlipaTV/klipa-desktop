import 'dart:async';

import 'package:flutter/services.dart';

abstract interface class AppWindowController {
  Future<bool> setFullscreen(bool enabled);

  Future<bool> isFullscreen();

  /// Full-screen changes the window made on its own, such as a window-manager
  /// shortcut. A runner that never leaves full screen by itself emits nothing.
  Stream<bool> get fullscreenChanges;
}

final class MethodChannelAppWindowController implements AppWindowController {
  const MethodChannelAppWindowController();

  static const _channel = MethodChannel('dev.klipa.player/window');

  static final _fullscreenChanges = StreamController<bool>.broadcast(
    onListen: () => _channel.setMethodCallHandler(_handleRunnerCall),
    onCancel: () => _channel.setMethodCallHandler(null),
  );

  static Future<void> _handleRunnerCall(MethodCall call) async {
    if (call.method == 'fullscreenChanged' && call.arguments is bool) {
      _fullscreenChanges.add(call.arguments as bool);
    }
  }

  @override
  Future<bool> setFullscreen(bool enabled) async =>
      await _channel.invokeMethod<bool>('setFullscreen', enabled) ?? false;

  @override
  Future<bool> isFullscreen() async =>
      await _channel.invokeMethod<bool>('isFullscreen') ?? false;

  @override
  Stream<bool> get fullscreenChanges => _fullscreenChanges.stream;
}
