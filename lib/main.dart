import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/call_service.dart';
import 'services/call_history_service.dart';
import 'services/call_result.dart';
import 'services/app_visibility.dart';
import 'services/system_call_service.dart';
import 'screens/call_screen.dart';
import 'screens/group_call_screen.dart';
import 'services/group_call_service.dart';
import 'screens/splash_screen.dart';
import 'theme/spartan_theme.dart';

final GlobalKey<NavigatorState> spartanNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> spartanMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService.init();

  AppVisibility.instance.initialize();
  await NotificationService.instance.initialize();

  CallService.instance.initialize();
  CallService.instance.externalCallBusy = () =>
      GroupCallService.instance.hasCall;
  GroupCallService.instance.initialize();
  CallHistoryService.initialize();

  if (!Platform.isWindows) {
    await Firebase.initializeApp();
    await SystemCallService.instance.initialize();

    await FirebaseMessagingService.instance.initialize();
  }

  runApp(const SpartanChatApp());
}

class SpartanChatApp extends StatelessWidget {
  const SpartanChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: spartanNavigatorKey,
      scaffoldMessengerKey: spartanMessengerKey,
      title: 'SPARTAN CHAT',
      debugShowCheckedModeBanner: false,
      theme: SpartanPalette.blueGoldTheme,
      builder: (context, child) {
        return CallNavigationHost(child: child ?? const SizedBox.shrink());
      },
      home: const SplashScreen(),
    );
  }
}

class CallNavigationHost extends StatefulWidget {
  const CallNavigationHost({super.key, required this.child});

  final Widget child;

  @override
  State<CallNavigationHost> createState() => _CallNavigationHostState();
}

class _CallNavigationHostState extends State<CallNavigationHost> {
  Route<void>? _callRoute;
  Route<void>? _groupCallRoute;
  int _shownGroupNotice = 0;
  bool _syncScheduled = false;
  String? _shownCallResult;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_scheduleSync);
    GroupCallService.instance.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_scheduleSync);
    GroupCallService.instance.removeListener(_scheduleSync);
    super.dispose();
  }

  void _scheduleSync() {
    if (!mounted || _syncScheduled) {
      return;
    }

    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncCallRoute();
    });
    // Incoming socket events do not necessarily schedule a Flutter frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncCallRoute() {
    final navigator = spartanNavigatorKey.currentState;

    if (navigator == null) {
      _scheduleSync();
      return;
    }

    final service = CallService.instance;
    final groupCall = GroupCallService.instance;
    if (groupCall.hasCall && _groupCallRoute == null && !service.hasCall) {
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Theme(
          data: SpartanPalette.blueGoldTheme,
          child: const GroupCallScreen(),
        ),
      );
      _groupCallRoute = route;
      navigator.push(route).whenComplete(() {
        if (_groupCallRoute == route) {
          _groupCallRoute = null;
          if (groupCall.hasCall) unawaited(groupCall.leave());
        }
      });
    } else if (!groupCall.hasCall && _groupCallRoute != null) {
      final route = _groupCallRoute!;
      _groupCallRoute = null;
      if (route.isActive) navigator.removeRoute(route);
    }
    if (groupCall.noticeSerial != _shownGroupNotice &&
        groupCall.notice != null) {
      _shownGroupNotice = groupCall.noticeSerial;
      spartanMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(groupCall.notice!)),
      );
    }

    if (service.hasCall && _callRoute == null) {
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            Theme(data: SpartanPalette.callTheme, child: const CallScreen()),
      );

      _callRoute = route;
      navigator.push(route).whenComplete(() {
        if (_callRoute == route) {
          _callRoute = null;
          if (CallService.instance.hasCall) {
            unawaited(CallService.instance.hangUp());
          }
        }
      });
      return;
    }

    if (!service.hasCall && _callRoute != null) {
      final route = _callRoute!;
      _callRoute = null;

      if (route.isActive) {
        navigator.removeRoute(route);
      }
    }
    final result = service.lastFinishedCall;
    if (!service.hasCall && result != null && _shownCallResult != result.id) {
      _shownCallResult = result.id;
      if (result.outcome == CallOutcome.missed ||
          result.outcome == CallOutcome.failed) {
        spartanMessengerKey.currentState?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('${result.peer}: ${result.message}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        CallService.instance,
        GroupCallService.instance,
      ]),
      builder: (context, _) => SpartanLightFrame(
        enabled:
            !CallService.instance.hasCall && !GroupCallService.instance.hasCall,
        child: widget.child,
      ),
    );
  }
}
