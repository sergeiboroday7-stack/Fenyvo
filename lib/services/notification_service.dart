import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  final FlutterLocalNotificationsPlugin
      _notifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<String>
      _notificationTapController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  String? _initialPayload;

  Stream<String> get notificationTapStream =>
      _notificationTapController.stream;

  // ========================================
  // ИНИЦИАЛИЗАЦИЯ
  // ========================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings =
        AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettings =
        InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse:
          _handleNotificationResponse,
    );

    final launchDetails =
        await _notifications
            .getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ==
        true) {
      final payload =
          launchDetails
              ?.notificationResponse
              ?.payload
              ?.trim();

      if (payload != null &&
          payload.isNotEmpty) {
        _initialPayload = payload;

        print(
          '🔔 Приложение открыто через уведомление: '
          '$payload',
        );
      }
    }

    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // ========================================
  // НАЖАТИЕ НА УВЕДОМЛЕНИЕ
  // ========================================

  void _handleNotificationResponse(
    NotificationResponse response,
  ) {
    final payload =
        response.payload?.trim();

    if (payload == null ||
        payload.isEmpty) {
      return;
    }

    print(
      '👆 Нажатие на уведомление: $payload',
    );

    _notificationTapController.add(
      payload,
    );
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

  // ========================================
  // СТАБИЛЬНЫЙ ID ДЛЯ СОБЕСЕДНИКА
  // ========================================

  int _messageNotificationId(
    String username,
  ) {
    final value =
        username.trim().toLowerCase();

    int hash = 17;

    for (final codeUnit in value.codeUnits) {
      hash =
          37 * hash + codeUnit;

      hash &=
          0x7fffffff;
    }

    return 100000 +
        (hash % 800000);
  }

  // ========================================
  // УВЕДОМЛЕНИЕ О НОВОМ СООБЩЕНИИ
  // ========================================

  Future<void> showMessageNotification({
    required String from,
    required String message,
  }) async {
    await initialize();

    final sender =
        from.trim();

    if (sender.isEmpty) {
      return;
    }

    const androidDetails =
        AndroidNotificationDetails(
      'spartan_messages',
      'Сообщения',
      channelDescription:
          'Уведомления о новых сообщениях',
      importance:
          Importance.max,
      priority:
          Priority.high,
      playSound:
          true,
      enableVibration:
          true,
      category:
          AndroidNotificationCategory.message,
    );

    const details =
        NotificationDetails(
      android:
          androidDetails,
    );

    await _notifications.show(
      id: _messageNotificationId(
        sender,
      ),
      title:
          sender,
      body:
          message,
      notificationDetails:
          details,
      payload:
          'message:$sender',
    );

    print(
      '🔔 Уведомление показано: '
      '$sender',
    );
  }

  // ========================================
  // УДАЛИТЬ УВЕДОМЛЕНИЯ ОТ СОБЕСЕДНИКА
  // ========================================

  Future<void> cancelMessageNotificationsFrom(
    String username,
  ) async {
    await initialize();

    final user =
        username.trim();

    if (user.isEmpty) {
      return;
    }

    final id =
        _messageNotificationId(
      user,
    );

    await _notifications.cancel(
      id: id,
    );

    print(
      '🧹 Уведомления удалены для: '
      '$user',
    );
  }

  // ========================================
  // УВЕДОМЛЕНИЕ О СЕРДЕЧКЕ
  // ========================================

  Future<void> showReactionNotification({
    required String from,
  }) async {
    await initialize();

    const androidDetails =
        AndroidNotificationDetails(
      'spartan_reactions',
      'Реакции',
      channelDescription:
          'Уведомления о реакциях на сообщения',
      importance:
          Importance.high,
      priority:
          Priority.high,
      playSound:
          true,
      enableVibration:
          true,
    );

    const details =
        NotificationDetails(
      android:
          androidDetails,
    );

    await _notifications.show(
      id: DateTime.now()
          .millisecondsSinceEpoch
          .remainder(
            100000,
          ),
      title:
          'Новая реакция ❤️',
      body:
          '$from поставил(а) сердечко',
      notificationDetails:
          details,
      payload:
          'reaction:$from',
    );
  }

  // ========================================
  // УДАЛИТЬ ВСЕ УВЕДОМЛЕНИЯ
  // ========================================

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}