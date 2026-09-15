import 'package:flutter/services.dart';

class WindowService {
  WindowService._();

  static const _channel = MethodChannel('sigg_launcher/window');

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // Running without the GTK runner (e.g. tests).
    }
  }

  static Future<void> show() async {
    try {
      await _channel.invokeMethod<void>('show');
    } on MissingPluginException {
      // Running without the GTK runner (e.g. tests).
    }
  }
}
