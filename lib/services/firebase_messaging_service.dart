import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';
import 'system_call_service.dart';
import 'socket_service.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static final FirebaseMessagingService instance =
      FirebaseMessagingService._();

  FirebaseMessaging get _messaging =>
      FirebaseMessaging.instance;

  final StreamController<String>
      _notificationTapController =
      StreamController<String>.broadcast();

  String? _token;

  String? _initialPayload;

  String? get token => _token;

  Stream<String> get notificationTapStream =>
      _notificationTapController.stream;

  Future<void> initialize() async {
    if (Platform.isWindows) {
      print(
        '🪟 Windows: FCM отключён',
      );
      return;
    }

    await _requestPermission();

    await _loadToken();

    await _loadInitialMessage();

    _listenTokenRefresh();

    _listenForegroundMessages();

    _listenNotificationTaps();
  }

  Future<void> _requestPermission() async {
    final settings =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print(
      '🔔 FCM permission: '
      '${settings.authorizationStatus}',
    );
  }

  Future<void> _loadToken() async {
    try {
      _token =
          await _messaging.getToken();

      if (_token != null &&
          _token!.isNotEmpty) {
        print('🔥 FCM token получен');
      } else {
        print(
          '⚠️ FCM token не получен',
        );
      }
    } catch (error) {
      print(
        '❌ Ошибка получения FCM token: '
        '$error',
      );
    }
  }

  // ========================================
  // FCM — ЗАПУСК ПРИЛОЖЕНИЯ ЧЕРЕЗ PUSH
  // ========================================

  Future<void> _loadInitialMessage() async {
    try {
      final message =
          await _messaging.getInitialMessage();

      if (message == null) {
        return;
      }

      final payload =
          _buildPayload(
        message,
      );

      if (payload == null ||
          payload.isEmpty) {
        return;
      }

      _initialPayload =
          payload;

      print(
        '🔥 Приложение запущено через FCM: '
        '$payload',
      );
    } catch (error) {
      print(
        '❌ Ошибка getInitialMessage: '
        '$error',
      );
    }
  }

  // ========================================
  // FCM — НАЖАТИЕ НА PUSH ИЗ ФОНА
  // ========================================

  void _listenNotificationTaps() {
    FirebaseMessaging.onMessageOpenedApp.listen(
      (
        RemoteMessage message,
      ) {
        final payload =
            _buildPayload(
          message,
        );

        if (payload == null ||
            payload.isEmpty) {
          return;
        }

        print(
          '👆 Нажатие на FCM уведомление: '
          '$payload',
        );

        _notificationTapController.add(
          payload,
        );
      },
      onError: (Object error) {
        print(
          '❌ Ошибка FCM notification tap: '
          '$error',
        );
      },
    );
  }

  // ========================================
  // ФОРМИРОВАНИЕ PAYLOAD
  // ========================================

  String? _buildPayload(
    RemoteMessage message,
  ) {
    final data =
        message.data;

    final type =
        data['type']
            ?.toString()
            .trim() ??
        '';

    final sender =
        data['sender']
            ?.toString()
            .trim() ??
        '';

    if (sender.isEmpty) {
      return null;
    }

    if (type == 'reaction') {
      return 'reaction:$sender';
    }

    return 'message:$sender';
  }

  // ========================================
  // ПОЛУЧИТЬ PAYLOAD ПРИ ЗАПУСКЕ
  // ========================================

  String? takeInitialPayload() {
    final payload =
        _initialPayload;

    _initialPayload = null;

    return payload;
  }

  void _listenTokenRefresh() {
    _messaging.onTokenRefresh.listen(
      (
        newToken,
      ) {
        _token =
            newToken;

        print('🔄 FCM token обновлён');
        SocketService.instance.registerCurrentFcmToken();
      },
      onError: (Object error) {
        print(
          '❌ Ошибка обновления FCM token: '
          '$error',
        );
      },
    );
  }

  void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen(
      (
        RemoteMessage message,
      ) {
        if (message.data['type'] == 'call_invite' || message.data['type'] == 'call_cancel') {
          unawaited(SystemCallService.instance.foregroundPush(message.data));
          return;
        }
        print(
          '📩 FCM сообщение получено '
          'при открытом приложении',
        );

        print(
          'FCM data: '
          '${message.data}',
        );

        final notification =
            message.notification;

        if (notification != null) {
          print(
            'FCM title: '
            '${notification.title}',
          );

          print(
            'FCM body: '
            '${notification.body}',
          );
        }

        final sender =
            message.data['sender']
                    ?.toString()
                    .trim() ??
                '';

        if (sender.isEmpty) {
          return;
        }

        final type =
            message.data['type']
                    ?.toString()
                    .trim() ??
                'message';

        if (type == 'reaction') {
          unawaited(
            NotificationService.instance
                .showReactionNotification(
              from: sender,
            ),
          );

          return;
        }

        final messageType =
            message.data['messageType']
                    ?.toString()
                    .trim() ??
                'text';

        final voiceDurationMs =
            int.tryParse(
          message.data['voiceDurationMs']
                  ?.toString() ??
              '',
        );

        final fileName =
            message.data['fileName']
                    ?.toString()
                    .trim();

        final body =
            notification?.body?.trim().isNotEmpty == true
                ? notification!.body!.trim()
                : message.data['preview']
                        ?.toString()
                        .trim() ??
                    'Новое сообщение';

        unawaited(
          NotificationService.instance
              .showMessageNotification(
            from: sender,
            message: body,
            messageType: messageType,
            voiceDurationMs: voiceDurationMs,
            fileName: fileName,
          ),
        );
      },
    );
  }
}
