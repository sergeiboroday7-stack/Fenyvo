import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// A selected conversation is not necessarily visible (minimized/unfocused).
class AppVisibility with WidgetsBindingObserver {
  AppVisibility._();
  static final instance = AppVisibility._();
  bool foreground = true;
  final ValueNotifier<bool> changes = ValueNotifier(true);
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    didChangeAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    changes.value = foreground;
  }

  static bool shouldNotify({
    required bool foreground,
    required bool sameChat,
  }) => !foreground || !sameChat;
  static Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    try {
      await const MethodChannel('spartan_chat/window')
          .invokeMethod<void>('show');
    } catch (_) {}
  }

  static Future<void> flashWindow() async {
    if (!Platform.isWindows) return;
    try {
      await const MethodChannel('spartan_chat/window')
          .invokeMethod<void>('flash');
    } catch (_) {}
  }
}
