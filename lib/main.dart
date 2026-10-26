import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/storage_service.dart';
import 'services/contact_link_service.dart';
import 'services/app_language_service.dart';
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
import 'theme/fenyvo_theme.dart';
import 'widgets/app_update_host.dart';
import 'services/windows_update_ready_service.dart';

class FenyvoRouteDiagnostics extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint(
      'FENYVO_NAV PUSH current=${route.runtimeType} previous=${previousRoute?.runtimeType}',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint(
      'FENYVO_NAV POP current=${route.runtimeType} previous=${previousRoute?.runtimeType}',
    );
  }
}

final ValueNotifier<int> groupCallReturnRequest = ValueNotifier<int>(0);

final GlobalKey<NavigatorState> spartanNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> spartanMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService.init();
  await AppLanguageService.instance.initialize();

  if (!Platform.isWindows) {
    await ContactLinkService.instance.initialize();
  }

  AppVisibility.instance.initialize();
  await NotificationService.instance.initialize();

  CallService.instance.initialize();
  CallService.instance.externalCallBusy = () =>
      GroupCallService.instance.hasCall;
  CallService.instance.leaveExternalCall = () =>
      GroupCallService.instance.leave();
  GroupCallService.instance.initialize();
  PulseService.instance.initialize();
  CallHistoryService.initialize();

  if (!Platform.isWindows) {
    await Firebase.initializeApp();
    await SystemCallService.instance.initialize();

    await FirebaseMessagingService.instance.initialize();
  }

  if (Platform.isWindows) {
    WindowsUpdateReadyService.initialize(args);
  }

  runApp(const FenyvoChatApp());
}

class FenyvoChatApp extends StatelessWidget {
  const FenyvoChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.instance.code,
      builder: (context, _, _) => MaterialApp(
        navigatorKey: spartanNavigatorKey,
        navigatorObservers: [FenyvoRouteDiagnostics(), groupCallRouteObserver],
        scaffoldMessengerKey: spartanMessengerKey,
        title: 'FENYVO',
        debugShowCheckedModeBanner: false,
        theme: FenyvoPalette.blueGoldTheme,
        locale: AppLanguageService.instance.locale,
        supportedLocales: AppLanguageService.languages
            .where((language) => language.code != 'system')
            .map((language) => Locale(language.code)),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return AppUpdateHost(
            navigatorKey: spartanNavigatorKey,
            child: CallNavigationHost(child: child ?? const SizedBox.shrink()),
          );
        },
        home: const SplashScreen(),
      ),
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
  int _handledGroupReturnRequest = 0;
  String? _shownCallResult;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_scheduleSync);
    GroupCallService.instance.addListener(_scheduleSync);
    groupCallReturnRequest.addListener(_scheduleSync);
    PulseService.instance.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_scheduleSync);
    GroupCallService.instance.removeListener(_scheduleSync);
    groupCallReturnRequest.removeListener(_scheduleSync);
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
    debugPrint(
      'FENYVO_GROUP_ROUTE hasCall=${groupCall.hasCall} phase=${groupCall.phase} routeExists=${_groupCallRoute != null} routeCurrent=${_groupCallRoute?.isCurrent} privateCall=${service.hasCall}',
    );
    if (groupCall.hasCall &&
        _groupCallRoute != null &&
        !_groupCallRoute!.isActive) {
      _groupCallRoute = null;
    }
    if (groupCall.hasCall && _groupCallRoute == null && !service.hasCall) {
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Theme(
          data: FenyvoPalette.blueGoldTheme,
          child: const GroupCallScreen(),
        ),
      );
      _groupCallRoute = route;
      navigator.push(route).whenComplete(() {
        if (_groupCallRoute == route) {
          _groupCallRoute = null;
          if (groupCall.hasCall) _scheduleSync();
        }
      });
    } else if (!groupCall.hasCall && _groupCallRoute != null) {
      final route = _groupCallRoute!;
      _groupCallRoute = null;
      if (route.isActive) navigator.removeRoute(route);
    }
    if (groupCallReturnRequest.value != _handledGroupReturnRequest) {
      _handledGroupReturnRequest = groupCallReturnRequest.value;
      final route = _groupCallRoute;
      if (groupCall.hasCall &&
          route != null &&
          route.isActive &&
          !route.isCurrent) {
        navigator.popUntil((candidate) => candidate == route);
      }
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
            Theme(data: FenyvoPalette.callTheme, child: const CallScreen()),
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

    if (service.phase == FenyvoPulsePhase.incoming &&
        pulse != null &&
        _shownPulseInviteId != pulse.id) {
      _shownPulseInviteId = pulse.id;
      messenger.hideCurrentSnackBar();
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.mediumImpact());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: FenyvoPalette.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Новый PULSE: ${pulse.from} · '
                  '${pulse.video ? 'видеозвонок' : 'аудиозвонок'}',
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (service.phase == FenyvoPulsePhase.matched &&
        pulse != null &&
        _shownPulseMatchId != pulse.id) {
      _shownPulseMatchId = pulse.id;
      messenger.hideCurrentSnackBar();
      unawaited(HapticFeedback.heavyImpact());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FenyvoPalette.surface,
          content: _PulseMatchCard(pulse: pulse),
        ),
      );
      return;
    }

    if (service.noticeSerial != _shownPulseNotice && service.notice != null) {
      _shownPulseNotice = service.noticeSerial;
      if (service.phase != FenyvoPulsePhase.incoming &&
          service.phase != FenyvoPulsePhase.matched) {
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
      builder: (context, _) => FenyvoLightFrame(
        enabled:
            !CallService.instance.hasCall && !GroupCallService.instance.hasCall,
        child: widget.child,
      ),
    );
  }
}

class _PulseMatchCard extends StatelessWidget {
  const _PulseMatchCard({required this.pulse});

  final FenyvoPulse pulse;

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
                color: FenyvoPalette.gold,
                boxShadow: [
                  BoxShadow(
                    color: FenyvoPalette.gold.withValues(alpha: .35),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                '$seconds',
                style: const TextStyle(
                  color: FenyvoPalette.onGold,
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
                      color: FenyvoPalette.gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${pulse.video ? 'Видеозвонок' : 'Аудиозвонок'} начинается…',
                    style: const TextStyle(color: FenyvoPalette.ink),
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
              icon: const Icon(Icons.close_rounded, color: FenyvoPalette.ink),
            ),
          ],
        );
      },
    );
  }
}
