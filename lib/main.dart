import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'services/pulse_service.dart';
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
  PulseService.instance.initialize();
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
  int _shownPulseNotice = 0;
  String? _shownPulseInviteId;
  String? _shownPulseMatchId;
  bool _syncScheduled = false;
  String? _shownCallResult;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_scheduleSync);
    GroupCallService.instance.addListener(_scheduleSync);
    PulseService.instance.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_scheduleSync);
    GroupCallService.instance.removeListener(_scheduleSync);
    PulseService.instance.removeListener(_scheduleSync);
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

    _syncPulseUi();

    if (service.shouldShowCallScreen && _callRoute == null) {
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            Theme(data: SpartanPalette.callTheme, child: const CallScreen()),
      );

      _callRoute = route;
      navigator.push(route).whenComplete(() {
        if (_callRoute == route) {
          _callRoute = null;
          if (CallService.instance.shouldShowCallScreen) {
            unawaited(CallService.instance.hangUp());
          }
        }
      });
      return;
    }

    if (!service.shouldShowCallScreen && _callRoute != null) {
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

  void _syncPulseUi() {
    final service = PulseService.instance;
    final messenger = spartanMessengerKey.currentState;
    final pulse = service.current;
    if (messenger == null) return;

    if (service.phase == SpartanPulsePhase.incoming &&
        pulse != null &&
        _shownPulseInviteId != pulse.id) {
      _shownPulseInviteId = pulse.id;
      messenger.hideCurrentSnackBar();
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.mediumImpact());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(days: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpartanPalette.surface,
          content: _PulseInviteCard(pulse: pulse),
        ),
      );
      return;
    }

    if (service.phase == SpartanPulsePhase.matched &&
        pulse != null &&
        _shownPulseMatchId != pulse.id) {
      _shownPulseMatchId = pulse.id;
      messenger.hideCurrentSnackBar();
      unawaited(HapticFeedback.heavyImpact());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpartanPalette.surface,
          content: _PulseMatchCard(pulse: pulse),
        ),
      );
      return;
    }

    if (service.noticeSerial != _shownPulseNotice && service.notice != null) {
      _shownPulseNotice = service.noticeSerial;
      if (service.phase != SpartanPulsePhase.incoming &&
          service.phase != SpartanPulsePhase.matched) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(service.notice!),
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
        PulseService.instance,
      ]),
      builder: (context, _) => SpartanLightFrame(
        enabled:
            !CallService.instance.hasCall && !GroupCallService.instance.hasCall,
        child: widget.child,
      ),
    );
  }
}

class _PulseInviteCard extends StatelessWidget {
  const _PulseInviteCard({required this.pulse});

  final SpartanPulse pulse;

  @override
  Widget build(BuildContext context) {
    final service = PulseService.instance;
    final mode = pulse.video ? 'видеозвонок' : 'аудиозвонок';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: SpartanPalette.blue,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SpartanPalette.gold),
              ),
              child: const Icon(Icons.bolt_rounded, color: SpartanPalette.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SPARTAN PULSE',
                    style: TextStyle(
                      color: SpartanPalette.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  Text(
                    '${pulse.from} предлагает $mode, когда вы оба готовы',
                    style: const TextStyle(color: SpartanPalette.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                service.decline();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              child: const Text('Не сейчас'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                service.accept();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Я готов'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PulseMatchCard extends StatelessWidget {
  const _PulseMatchCard({required this.pulse});

  final SpartanPulse pulse;

  @override
  Widget build(BuildContext context) {
    final service = PulseService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final seconds = service.countdownSeconds;
        return Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SpartanPalette.gold,
                boxShadow: [
                  BoxShadow(
                    color: SpartanPalette.gold.withValues(alpha: .35),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                '$seconds',
                style: const TextStyle(
                  color: SpartanPalette.onGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ОБА ГОТОВЫ',
                    style: TextStyle(
                      color: SpartanPalette.gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${pulse.video ? 'Видеозвонок' : 'Аудиозвонок'} начинается…',
                    style: const TextStyle(color: SpartanPalette.ink),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Отменить',
              onPressed: () {
                service.cancel();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              icon: const Icon(Icons.close_rounded, color: SpartanPalette.ink),
            ),
          ],
        );
      },
    );
  }
}
