import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_visibility.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  Future<void>? _initializing;

  String? _initialPayload;

  Stream<String> get notificationTapStream => _notificationTapController.stream;

  // ========================================
  // ИНИЦИАЛИЗАЦИЯ
  // ========================================

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object error) {
        _initializing = null;
        print('Ошибка инициализации уведомлений: $error');
      });

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    final windowsSettings = WindowsInitializationSettings(
      appName: 'FENYVO',
      appUserModelId: 'Fenyvo.Messenger.Desktop',
      guid: '4d7db11e-4595-47d1-907d-5b70f384d9c7',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    if (Platform.isAndroid) {
      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();

      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload?.trim();

        if (payload != null && payload.isNotEmpty) {
          _initialPayload = payload;

          print(
            '🔔 Приложение открыто через уведомление: '
            '$payload',
          );
        }
      }
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.requestNotificationsPermission();
    }

    _initialized = true;

    print(
      Platform.isWindows
          ? '🪟🔔 Windows local notifications готовы'
          : '🔔 Local notifications готовы',
    );
  }

  // ========================================
  // НАЖАТИЕ НА УВЕДОМЛЕНИЕ
  // ========================================

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload?.trim();

    if (payload == null || payload.isEmpty) {
      return;
    }

    print('👆 Нажатие на уведомление: $payload');

    _notificationTapController.add(payload);
    unawaited(AppVisibility.showWindow());
  }

  Future<void> showIncomingCall({
    required String id,
    required String from,
    required bool video,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await initialize();
      await _notifications.show(
        id: _messageNotificationId('call:$id'),
        title: from,
        body: video
            ? 'Входящий видеозвонок — открыть FENYVO'
            : 'Входящий аудиозвонок — открыть FENYVO',
        notificationDetails: NotificationDetails(
          windows: WindowsNotificationDetails(
            duration: WindowsNotificationDuration.short,
            audio: WindowsNotificationAudio.silent(),
          ),
        ),
        payload: 'call:$id',
      );
    } catch (error) {
      print('Уведомление звонка недоступно: $error');
    }
  }

  // ========================================
  // ПОЛУЧИТЬ PAYLOAD ПРИ ЗАПУСКЕ
  // ========================================

  Future<void> showMissedCall({
    required String id,
    required String from,
    required bool video,
  }) async {
    await initialize();
    await _notifications.show(
      id: _messageNotificationId('missed:$id'),
      title: from,
      body: video ? 'Пропущенный видеозвонок' : 'Пропущенный звонок',
      notificationDetails: NotificationDetails(
        windows: WindowsNotificationDetails(
          audio: WindowsNotificationAudio.preset(
            sound: WindowsNotificationSound.im,
          ),
        ),
      ),
      payload: 'message:$from',
    );
  }

  String? takeInitialPayload() {
    final payload = _initialPayload;

    _initialPayload = null;

    return payload;
  }

  // ========================================
  // СТАБИЛЬНЫЙ ID ДЛЯ СОБЕСЕДНИКА
  // ========================================

  int _messageNotificationId(String username) {
    final value = username.trim().toLowerCase();

    int hash = 17;

    for (final codeUnit in value.codeUnits) {
      hash = 37 * hash + codeUnit;

      hash &= 0x7fffffff;
    }

    return 100000 + (hash % 800000);
  }

  int _groupNotificationId(String groupId) {
    final value = groupId.trim().toLowerCase();

    int hash = 23;

    for (final codeUnit in value.codeUnits) {
      hash = 41 * hash + codeUnit;
      hash &= 0x7fffffff;
    }

    return 900000 + (hash % 800000);
  }

  // ========================================
  // УВЕДОМЛЕНИЕ О НОВОМ СООБЩЕНИИ
  // ========================================

  Future<void> showMessageNotification({
    required String from,
    required String message,
    String? messageType,
    Object? voiceDurationMs,
    String? fileName,
  }) async {
    await initialize();

    final sender = from.trim();

    if (sender.isEmpty) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'spartan_messages',
      'Сообщения',
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.message,
    );

    final windowsDetails = WindowsNotificationDetails(
      audio: WindowsNotificationAudio.preset(
        sound: WindowsNotificationSound.im,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: _messageNotificationId(sender),
      title: sender,
      body: message,
      notificationDetails: details,
      payload: 'message:$sender',
    );

    print(
      '🔔 Уведомление показано со звуком Windows IM: '
      '$sender',
    );
  }

  Future<void> showGroupMessageNotification({
    required String groupId,
    required String from,
    required String message,
  }) async {
    await initialize();

    final id = groupId.trim();
    final sender = from.trim();

    if (id.isEmpty || sender.isEmpty) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'spartan_group_messages',
      'Группы',
      channelDescription: 'Уведомления о новых сообщениях в группах',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.message,
    );

    final windowsDetails = WindowsNotificationDetails(
      audio: WindowsNotificationAudio.preset(
        sound: WindowsNotificationSound.im,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: _groupNotificationId(id),
      title: 'Группа · $sender',
      body: message,
      notificationDetails: details,
      payload: 'group:$id',
    );

    print(
      '👥🔔 Уведомление группы показано со звуком Windows IM: '
      '$sender',
    );
  }

  // ========================================
  // УДАЛИТЬ УВЕДОМЛЕНИЯ ОТ СОБЕСЕДНИКА
  // ========================================

  Future<void> cancelMessageNotificationsFrom(String username) async {
    await initialize();

    final user = username.trim();

    if (user.isEmpty) {
      return;
    }

    final id = _messageNotificationId(user);

    await _notifications.cancel(id: id);

    print(
      '🧹 Уведомления удалены для: '
      '$user',
    );
  }

  // ========================================
  // УВЕДОМЛЕНИЕ О СЕРДЕЧКЕ
  // ========================================

  Future<void> showReactionNotification({required String from}) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'spartan_reactions',
      'Реакции',
      channelDescription: 'Уведомления о реакциях на сообщения',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final windowsDetails = WindowsNotificationDetails(
      audio: WindowsNotificationAudio.preset(
        sound: WindowsNotificationSound.im,
      ),
    );

    final details = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: 'Новая реакция ❤️',
      body: '$from поставил(а) сердечко',
      notificationDetails: details,
      payload: 'reaction:$from',
    );
  }

  // ========================================
  // УДАЛИТЬ ВСЕ УВЕДОМЛЕНИЯ
  // ========================================

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
