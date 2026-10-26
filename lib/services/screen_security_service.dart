import 'dart:io';

import 'package:flutter/services.dart';

class ScreenSecurityService {
  ScreenSecurityService._();

  static const MethodChannel _channel = MethodChannel('fenyvo/screen_security');

  static Future<void> setSecure(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isWindows) return;

    await _channel.invokeMethod<void>('setSecure', <String, dynamic>{
      'enabled': enabled,
    });
  }
}
