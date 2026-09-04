import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_messaging_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

class SocketService {
  static final SocketService _instance =
      SocketService._internal();

  static SocketService get instance =>
      _instance;

  SocketService._internal();

  WebSocketChannel? _channel;

  final List<
      void Function(
        Map<String, dynamic>,
      )> _messageHandlers = [];

  String? currentUser;

  String? _activeChatUser;

  bool _isConnected = false;

  bool _manualDisconnect = false;

  Timer? _reconnectTimer;

  bool _isReconnecting = false;

  bool _receivingOfflineMessages = false;

  String? _serverUrl;

  String? _lastPassword;

  bool get isConnected =>
      _isConnected;

  String? get activeChatUser =>
      _activeChatUser;

  // ========================================
  // АКТИВНЫЙ ЧАТ
  // ========================================

  void setActiveChatUser(
    String username,
  ) {
    final user =
        username.trim();

    if (user.isEmpty) {
      _activeChatUser = null;
      return;
    }

    _activeChatUser = user;

    print(
      '💬 Активный чат: $user',
    );
  }

  void clearActiveChatUser([
    String? username,
  ]) {
    final user =
        username?.trim() ?? '';

    if (user.isNotEmpty &&
        _activeChatUser != user) {
      return;
    }

    if (_activeChatUser != null) {
      print(
        '💬 Активный чат закрыт: '
        '$_activeChatUser',
      );
    }

    _activeChatUser = null;
  }

  // ========================================
  // ОБРАБОТЧИКИ
  // ========================================

  void addMessageHandler(
    void Function(
      Map<String, dynamic>,
    ) handler,
  ) {
    if (!_messageHandlers.contains(handler)) {
      _messageHandlers.add(handler);
    }
  }

  void removeMessageHandler(
    void Function(
      Map<String, dynamic>,
    ) handler,
  ) {
    _messageHandlers.remove(handler);
  }

  void _notifyHandlers(
    Map<String, dynamic> message,
  ) {
    final handlers =
        List<
            void Function(
              Map<String, dynamic>,
            )>.from(
      _messageHandlers,
    );

    for (final handler in handlers) {
      try {
        handler(message);
      } catch (error) {
        print(
          '❌ Ошибка обработчика: $error',
        );
      }
    }
  }

  // ========================================
  // ПОДКЛЮЧЕНИЕ
  // ========================================

  Future<bool> connect(
    String url,
  ) async {
    if (_isConnected &&
        _serverUrl == url &&
        _channel != null) {
      return true;
    }

    _serverUrl = url;

    _manualDisconnect = false;

    _reconnectTimer?.cancel();

    _isReconnecting = false;

    try {
      print(
        '🔌 Подключение к серверу: $url',
      );

      if (_channel != null) {
        try {
          await _channel!.sink.close();
        } catch (_) {}

        _channel = null;
      }

      final uri =
          Uri.parse(
        url,
      );

      _channel =
          WebSocketChannel.connect(
        uri,
      );

      _channel!.stream.listen(
        _handleRawMessage,
        onError: (Object error) {
          print(
            '❌ Ошибка WebSocket: $error',
          );

          _handleDisconnect(
            reason:
                'Ошибка подключения к серверу',
          );
        },
        onDone: () {
          print(
            '🔴 WebSocket отключён',
          );

          _handleDisconnect(
            reason:
                'Соединение с сервером закрыто',
          );
        },
        cancelOnError: false,
      );

      _isConnected = true;

      print(
        '✅ WebSocket подключён',
      );

      return true;
    } catch (error) {
      print(
        '❌ Не удалось подключиться: $error',
      );

      _isConnected = false;

      _channel = null;

      return false;
    }
  }

  // ========================================
  // ПОЛУЧЕНИЕ СООБЩЕНИЙ
  // ========================================

  void _handleRawMessage(
    dynamic rawMessage,
  ) {
    try {
      final decoded =
          jsonDecode(
        rawMessage.toString(),
      );

      if (decoded is! Map) {
        return;
      }

      final message =
          Map<String, dynamic>.from(
        decoded,
      );

      final type =
          message['type']?.toString() ?? '';

      final rawData =
          message['data'];

      final data =
          rawData is Map
              ? Map<String, dynamic>.from(
                  rawData,
                )
              : <String, dynamic>{};

      print(
        '📨 ПОЛУЧЕНО: $type',
      );

      // ======================================
      // УСПЕШНЫЙ ВХОД
      // ======================================

      if (type == 'login_success') {
        final username =
            data['username']
                ?.toString();

        if (username != null &&
            username.isNotEmpty) {
          currentUser = username;

          print(
            '👤 Текущий пользователь: '
            '$currentUser',
          );

          _sendFcmToken();
        }
      }

      // ======================================
      // ОФЛАЙН-СООБЩЕНИЯ ПОЛУЧЕНЫ
      // ======================================

      if (type ==
          'offline_messages_complete') {
        _receivingOfflineMessages =
            false;

        print(
          '📭 Получение офлайн-сообщений завершено',
        );
      }

      // ======================================
      // ВХОДЯЩЕЕ СООБЩЕНИЕ
      // ======================================

      if (type == 'message') {
        final id =
            data['id']
                    ?.toString()
                    .trim() ??
                '';

        final from =
            data['from']
                    ?.toString()
                    .trim() ??
                '';

        final to =
            data['to']
                    ?.toString()
                    .trim() ??
                '';

        final text =
            data['text']
                    ?.toString()
                    .trim() ??
                '';

        // Сообщение реально дошло до приложения.
        // Подтверждаем доставку серверу.
        if (id.isNotEmpty &&
            from.isNotEmpty &&
            to.isNotEmpty &&
            currentUser != null &&
            currentUser!.isNotEmpty &&
            to == currentUser &&
            from != currentUser) {
          sendMessageDelivered(
            messageId: id,
            from: from,
            to: to,
          );
        }

        // Уведомление показываем только если:
        // 1. сообщение не от самого себя;
        // 2. это не повтор офлайн-сообщений;
        // 3. чат с этим человеком НЕ открыт.
        if (from.isNotEmpty &&
            text.isNotEmpty &&
            from != currentUser &&
            from != _activeChatUser &&
            !_receivingOfflineMessages) {
          unawaited(
            NotificationService.instance
                .showMessageNotification(
              from: from,
              message: text,
            ),
          );

          print(
            '🔔 Уведомление о сообщении: '
            '$from',
          );
        } else if (from.isNotEmpty &&
            from == _activeChatUser) {
          print(
            '💬 Чат с $from открыт — '
            'уведомление не показываем',
          );
        }
      }

      // ======================================
      // ПОДТВЕРЖДЕНИЕ ДОСТАВКИ
      // ======================================

      if (type ==
          'message_delivered') {
        final messageId =
            data['messageId']
                    ?.toString()
                    .trim() ??
                '';

        if (messageId.isNotEmpty) {
          print(
            '✓✓ Сообщение доставлено: '
            '$messageId',
          );
        }
      }

      // ======================================
      // ПОДТВЕРЖДЕНИЕ ПРОЧТЕНИЯ
      // ======================================

      if (type == 'message_read') {
        final messageId =
            data['messageId']
                    ?.toString()
                    .trim() ??
                '';

        if (messageId.isNotEmpty) {
          print(
            '👁️ Сообщение прочитано: '
            '$messageId',
          );
        }
      }

      // ======================================
      // СООБЩЕНИЕ УДАЛЕНО ДЛЯ ВСЕХ
      // ======================================

      if (type == 'message_deleted') {
        final messageId =
            data['messageId']?.toString().trim() ?? '';
        final from =
            data['from']?.toString().trim() ?? '';
        final to =
            data['to']?.toString().trim() ?? '';
        final user = currentUser?.trim() ?? '';

        if (messageId.isNotEmpty &&
            from.isNotEmpty &&
            to.isNotEmpty &&
            user.isNotEmpty &&
            (user == from || user == to)) {
          final otherUser =
              user == from ? to : from;

          StorageService.deleteMessageWithoutTrace(
            user,
            otherUser,
            messageId,
          );

          StorageService.removePinnedMessage(
            user,
            otherUser,
            messageId,
          );

          print(
            '🧹 Сообщение удалено для всех: $messageId',
          );
        }
      }

      if (type == 'message_pinned' ||
          type == 'message_unpinned') {
        final from =
            data['from']?.toString().trim() ?? '';
        final to =
            data['to']?.toString().trim() ?? '';
        final user = currentUser?.trim() ?? '';

        if (from.isNotEmpty &&
            to.isNotEmpty &&
            user.isNotEmpty &&
            (user == from || user == to)) {
          final otherUser =
              user == from ? to : from;

          if (type == 'message_pinned') {
            StorageService.addPinnedMessage(
              user,
              otherUser,
              data,
            );
          } else {
            StorageService.removePinnedMessage(
              user,
              otherUser,
              data['messageId']
                      ?.toString()
                      .trim() ??
                  '',
            );
          }
        }
      }

      // ======================================
      // УВЕДОМЛЕНИЕ О СЕРДЕЧКЕ
      // ======================================

      if (type == 'reaction_update') {
        final changedBy =
            data['changedBy']
                    ?.toString()
                    .trim() ??
                '';

        final reactionAdded =
            data['reactionAdded'] ==
                true;

        if (reactionAdded &&
            changedBy.isNotEmpty &&
            changedBy != currentUser) {
          unawaited(
            NotificationService.instance
                .showReactionNotification(
              from: changedBy,
            ),
          );

          print(
            '❤️ Уведомление о реакции: '
            '$changedBy',
          );
        }
      }

      // ======================================
      // АВАТАРКА ОТ СЕРВЕРА
      // ======================================

      if (type == 'avatar_data') {
        final username =
            data['username']
                    ?.toString() ??
                '';

        final avatar =
            data['avatar']
                    ?.toString() ??
                '';

        if (username.isNotEmpty) {
          if (avatar.isNotEmpty) {
            StorageService.saveAvatar(
              username,
              avatar,
            );

            print(
              '🖼️ Аватарка получена и сохранена: '
              '$username',
            );
          } else {
            StorageService.removeAvatar(
              username,
            );

            print(
              '🗑️ У пользователя нет аватарки: '
              '$username',
            );
          }
        }
      }

      // ======================================
      // АВАТАРКА ОБНОВЛЕНА
      // ======================================

      if (type ==
          'avatar_updated') {
        final username =
            data['username']
                    ?.toString() ??
                '';

        if (username.isNotEmpty) {
          requestAvatar(
            username,
          );
        }
      }

      // ======================================
      // ПЕРЕДАЁМ СОБЫТИЕ ЭКРАНАМ
      // ======================================

      _notifyHandlers(
        message,
      );
    } catch (error) {
      print(
        '❌ Ошибка обработки сообщения: $error',
      );
    }
  }

  // ========================================
  // FCM TOKEN
  // ========================================

  void _sendFcmToken() {
    final username =
        currentUser?.trim() ?? '';

    final token =
        FirebaseMessagingService
                .instance
                .token
                ?.trim() ??
            '';

    if (username.isEmpty) {
      print(
        '⚠️ FCM token не отправлен: '
        'нет пользователя',
      );

      return;
    }

    if (token.isEmpty) {
      print(
        '⚠️ FCM token не отправлен: '
        'token пустой',
      );

      return;
    }

    _send(
      'register_fcm_token',
      {
        'token': token,
      },
    );

    print(
      '🔥 FCM token отправлен на сервер '
      'для $username',
    );
  }

  // ========================================
  // ПОТЕРЯ СОЕДИНЕНИЯ
  // ========================================

  void _handleDisconnect({
    required String reason,
  }) {
    _isConnected = false;

    _channel = null;

    _receivingOfflineMessages =
        false;

    if (_manualDisconnect) {
      print(
        '⛔ Ручной выход. '
        'Переподключение запрещено.',
      );

      return;
    }

    _notifyHandlers(
      {
        'type':
            'disconnected',
        'data': {
          'reason':
              reason,
        },
      },
    );

    _scheduleReconnect();
  }

  // ========================================
  // ПЕРЕПОДКЛЮЧЕНИЕ
  // ========================================

  void _scheduleReconnect() {
    if (_manualDisconnect) {
      return;
    }

    if (_isReconnecting) {
      return;
    }

    if (_serverUrl == null ||
        _serverUrl!.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty ||
        _lastPassword == null ||
        _lastPassword!.isEmpty) {
      return;
    }

    _isReconnecting = true;

    _reconnectTimer?.cancel();

    _reconnectTimer =
        Timer(
      const Duration(
        seconds: 5,
      ),
      () async {
        _isReconnecting = false;

        if (_manualDisconnect) {
          return;
        }

        final url =
            _serverUrl;

        final username =
            currentUser;

        final password =
            _lastPassword;

        if (url == null ||
            username == null ||
            password == null) {
          return;
        }

        print(
          '🔄 Попытка переподключения...',
        );

        final connected =
            await connect(
          url,
        );

        if (connected &&
            !_manualDisconnect) {
          login(
            username,
            password,
          );
        }
      },
    );
  }

  // ========================================
  // ОТПРАВКА НА СЕРВЕР
  // ========================================

  void _send(
    String type,
    Map<String, dynamic> data,
  ) {
    if (!_isConnected ||
        _channel == null) {
      print(
        '⚠️ Нет подключения. '
        'Не отправлено: $type',
      );

      return;
    }

    final message = {
      'type': type,
      'data': data,
    };

    try {
      final json =
          jsonEncode(
        message,
      );

      print(
        '📤 Отправлено: $type',
      );

      _channel!.sink.add(
        json,
      );
    } catch (error) {
      print(
        '❌ Ошибка отправки: $error',
      );
    }
  }

  // ========================================
  // РЕГИСТРАЦИЯ
  // ========================================

  void register(
    String username,
    String password,
  ) {
    _send(
      'register',
      {
        'username':
            username.trim(),
        'password':
            password,
      },
    );
  }

  // ========================================
  // ВХОД
  // ========================================

  void login(
    String username,
    String password,
  ) {
    final user =
        username.trim();

    if (user.isEmpty ||
        password.isEmpty) {
      return;
    }

    _manualDisconnect = false;

    currentUser = user;

    _lastPassword = password;

    _send(
      'login',
      {
        'username': user,
        'password': password,
      },
    );
  }

  // ========================================
  // ПОЛЬЗОВАТЕЛИ
  // ========================================

  void getUsers() {
    _send(
      'get_users',
      {},
    );
  }

  // ========================================
  // ОФЛАЙН-СООБЩЕНИЯ
  // ========================================

  void getOfflineMessages() {
    _receivingOfflineMessages =
        true;

    _send(
      'get_offline_messages',
      {},
    );
  }

  // ========================================
  // СТАТУС КОНТАКТА / LAST SEEN
  // ========================================

  void getUserStatus(
    String username,
  ) {
    final user =
        username.trim();

    if (user.isEmpty) {
      return;
    }

    _send(
      'get_user_status',
      {
        'username': user,
      },
    );
  }

  // ========================================
  // ПЕЧАТАЕТ / TYPING
  // ========================================

  void sendTyping(
    String to,
    bool isTyping,
  ) {
    final target =
        to.trim();

    if (target.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty) {
      return;
    }

    _send(
      'typing',
      {
        'to': target,
        'isTyping': isTyping,
      },
    );
  }

  // ========================================
  // СООБЩЕНИЕ
  // ========================================

  void sendMessage(
    String to,
    String text, {
    Map<String, dynamic>? replyTo,
    String? forwardedFrom,
    String? forwardComment,
  }) {
    final target =
        to.trim();

    final messageText =
        text.trim();

    if (target.isEmpty ||
        messageText.isEmpty) {
      return;
    }

    final messageData =
        <String, dynamic>{
      'id':
          DateTime.now()
              .microsecondsSinceEpoch
              .toString(),
      'to':
          target,
      'text':
          messageText,
      'time':
          DateTime.now()
              .toIso8601String(),
    };

    if (replyTo != null) {
      final replyId =
          replyTo['id']
                  ?.toString()
                  .trim() ??
              '';

      final replyFrom =
          replyTo['from']
                  ?.toString()
                  .trim() ??
              '';

      final replyText =
          replyTo['text']
                  ?.toString()
                  .trim() ??
              '';

      if (replyId.isNotEmpty &&
          replyFrom.isNotEmpty &&
          replyText.isNotEmpty) {
        messageData['replyTo'] = {
          'id':
              replyId,
          'from':
              replyFrom,
          'text':
              replyText,
        };
      }
    }

    final originalAuthor =
        forwardedFrom?.trim() ?? '';

    if (originalAuthor.isNotEmpty) {
      messageData['forwardedFrom'] =
          originalAuthor;
    }

    final comment =
        forwardComment?.trim() ?? '';

    if (comment.isNotEmpty) {
      messageData['forwardComment'] =
          comment;
    }

    _send(
      'message',
      messageData,
    );
  }

  // ========================================
  // РЕДАКТИРОВАНИЕ СООБЩЕНИЯ
  // ========================================

  void editMessage({
    required String messageId,
    required String to,
    required String newText,
  }) {
    final id =
        messageId.trim();

    final target =
        to.trim();

    final text =
        newText.trim();

    if (id.isEmpty ||
        target.isEmpty ||
        text.isEmpty) {
      return;
    }

    _send(
      'edit_message',
      {
        'messageId': id,
        'to': target,
        'newText': text,
      },
    );
  }

  // ========================================
  // УДАЛЕНИЕ СООБЩЕНИЯ ДЛЯ ВСЕХ
  // ========================================

  void deleteMessageForEveryone({
    required String messageId,
    required String to,
  }) {
    final id = messageId.trim();
    final target = to.trim();

    if (id.isEmpty ||
        target.isEmpty ||
        currentUser == null ||
        currentUser!.isEmpty) {
      return;
    }

    _send(
      'delete_message',
      {
        'messageId': id,
        'to': target,
      },
    );
  }

  void setPinnedMessage({
    required String messageId,
    required String to,
    required bool pinned,
    String messageFrom = '',
    String text = '',
  }) {
    final id = messageId.trim();
    final target = to.trim();

    if (id.isEmpty ||
        target.isEmpty ||
        currentUser == null ||
        currentUser!.isEmpty) {
      return;
    }

    _send(
      pinned ? 'pin_message' : 'unpin_message',
      {
        'messageId': id,
        'to': target,
        'messageFrom': messageFrom.trim(),
        'text': text.trim(),
      },
    );
  }

  // ========================================
  // СООБЩЕНИЕ ДОСТАВЛЕНО
  // ========================================

  void sendMessageDelivered({
    required String messageId,
    required String from,
    required String to,
  }) {
    final id =
        messageId.trim();

    final messageFrom =
        from.trim();

    final messageTo =
        to.trim();

    if (id.isEmpty ||
        messageFrom.isEmpty ||
        messageTo.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty ||
        currentUser != messageTo) {
      return;
    }

    _send(
      'message_delivered',
      {
        'messageId':
            id,
        'from':
            messageFrom,
        'to':
            messageTo,
      },
    );
  }

  // ========================================
  // СООБЩЕНИЕ ПРОЧИТАНО
  // ========================================

  void sendMessageRead({
    required String messageId,
    required String from,
    required String to,
  }) {
    final id =
        messageId.trim();

    final messageFrom =
        from.trim();

    final messageTo =
        to.trim();

    if (id.isEmpty ||
        messageFrom.isEmpty ||
        messageTo.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty ||
        currentUser != messageTo) {
      return;
    }

    _send(
      'message_read',
      {
        'messageId':
            id,
        'from':
            messageFrom,
        'to':
            messageTo,
      },
    );
  }

  // ========================================
  // РЕАКЦИЯ НА СООБЩЕНИЕ
  // ========================================

  void sendMessageReaction({
    required String messageId,
    required String from,
    required String to,
    required String reaction,
  }) {
    final id =
        messageId.trim();

    final messageFrom =
        from.trim();

    final messageTo =
        to.trim();

    final selectedReaction =
        reaction.trim();

    if (id.isEmpty ||
        messageFrom.isEmpty ||
        messageTo.isEmpty ||
        selectedReaction.isEmpty) {
      return;
    }

    _send(
      'message_reaction',
      {
        'messageId':
            id,
        'from':
            messageFrom,
        'to':
            messageTo,
        'reaction':
            selectedReaction,
      },
    );
  }

  // ========================================
  // ЗАГРУЗКА АВАТАРКИ
  // ========================================

  Future<void> setAvatarFromPath(
    String path,
  ) async {
    try {
      if (currentUser == null ||
          currentUser!.isEmpty) {
        print(
          '⚠️ Пользователь не авторизован',
        );

        return;
      }

      final file =
          File(
        path,
      );

      if (!await file.exists()) {
        print(
          '❌ Файл аватарки не найден: '
          '$path',
        );

        return;
      }

      final bytes =
          await file.readAsBytes();

      final avatarBase64 =
          base64Encode(
        bytes,
      );

      StorageService.saveAvatar(
        currentUser!,
        avatarBase64,
      );

      _send(
        'upload_avatar',
        {
          'avatar':
              avatarBase64,
        },
      );

      print(
        '🖼️ Аватарка отправлена на сервер',
      );
    } catch (error) {
      print(
        '❌ Ошибка загрузки аватарки: '
        '$error',
      );
    }
  }

  // ========================================
  // ЗАПРОС АВАТАРКИ
  // ========================================

  void requestAvatar(
    String username,
  ) {
    final user =
        username.trim();

    if (user.isEmpty) {
      return;
    }

    _send(
      'get_avatar',
      {
        'username':
            user,
      },
    );
  }

  // ========================================
  // УДАЛЕНИЕ АВАТАРКИ
  // ========================================

  Future<void> deleteAvatar() async {
    final username =
        currentUser;

    if (username == null ||
        username.isEmpty) {
      return;
    }

    _send(
      'delete_avatar',
      {},
    );

    await StorageService.removeAvatar(
      username,
    );

    print(
      '🗑️ Аватарка удалена',
    );
  }

  // ========================================
  // РУЧНОЙ ВЫХОД
  // ========================================

  Future<void> disconnect({
    bool clearUser = true,
  }) async {
    _manualDisconnect = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _isReconnecting = false;

    _receivingOfflineMessages =
        false;

    final channel =
        _channel;

    if (clearUser) {
      _activeChatUser = null;
      currentUser = null;
      _lastPassword = null;
    }

    _channel = null;

    _isConnected = false;

    try {
      await channel?.sink.close();
    } catch (_) {}

    print(
      '🔌 Ручной выход. '
      'Автовход отключён.',
    );
  }
}
