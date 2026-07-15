import 'package:flutter/services.dart';

abstract interface class AppWindowController {
  Future<bool> setFullscreen(bool enabled);

  Future<bool> isFullscreen();
}

final class MethodChannelAppWindowController implements AppWindowController {
  const MethodChannelAppWindowController();

  static const _channel = MethodChannel('dev.klipa.player/window');

  @override
  Future<bool> setFullscreen(bool enabled) async =>
      await _channel.invokeMethod<bool>('setFullscreen', enabled) ?? false;

  @override
  Future<bool> isFullscreen() async =>
      await _channel.invokeMethod<bool>('isFullscreen') ?? false;
}
