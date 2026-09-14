import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_messaging_service.dart';
import 'media_transfer_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'app_visibility.dart';
import 'system_call_service.dart';
import 'e2ee_settings_service.dart';
import 'crypto/signal_e2ee_service.dart';

enum SpartanConnectionPhase {
  disconnected,
  connecting,
  authenticating,
  connected,
}

class SocketService {
  static final SocketService _instance = SocketService._internal();

  static SocketService get instance => _instance;

  SocketService._internal();

  WebSocketChannel? _channel;

  final List<void Function(Map<String, dynamic>)> _messageHandlers = [];

  String? currentUser;

  String? _activeChatUser;
  String? activeGroupId;
  void registerCurrentFcmToken() => _sendFcmToken();

  bool _isConnected = false;
  bool _authenticated = false;
  bool get isAuthenticated => _isConnected && _authenticated;

  final ValueNotifier<SpartanConnectionPhase> connectionPhase =
      ValueNotifier<SpartanConnectionPhase>(
        SpartanConnectionPhase.disconnected,
      );

  bool _manualDisconnect = false;

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _isReconnecting = false;

  bool _receivingOfflineMessages = false;

  bool _needsResyncAfterLogin = false;

  bool _flushingOutbox = false;

  bool _e2eeEnabled = false;
  Set<String> _e2eeActivePeers = <String>{};
  final Map<String, Completer<Map<String, dynamic>>> _e2eeBundleRequests = {};
  final Set<String> _e2eeSendingIds = <String>{};
  Completer<bool>? _e2eePublishRequest;

  bool get e2eeEnabled => _e2eeEnabled;

  bool isE2eeActiveWith(String username) =>
      _e2eeEnabled && _e2eeActivePeers.contains(username.trim());

  String? _serverUrl;

  String? _lastPassword;

  bool get isConnected => _isConnected;

  String? get activeChatUser => _activeChatUser;

  // ========================================
  // АКТИВНЫЙ ЧАТ
  // ========================================

  void setActiveChatUser(String username) {
    final user = username.trim();

    if (user.isEmpty) {
      _activeChatUser = null;
      return;
    }

    _activeChatUser = user;

    print('💬 Активный чат: $user');
  }

  void clearActiveChatUser([String? username]) {
    final user = username?.trim() ?? '';

    if (user.isNotEmpty && _activeChatUser != user) {
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

  void addMessageHandler(void Function(Map<String, dynamic>) handler) {
    if (!_messageHandlers.contains(handler)) {
      _messageHandlers.add(handler);
    }
  }

  void removeMessageHandler(void Function(Map<String, dynamic>) handler) {
    _messageHandlers.remove(handler);
  }

  void _notifyHandlers(Map<String, dynamic> message) {
    final handlers = List<void Function(Map<String, dynamic>)>.from(
      _messageHandlers,
    );

    for (final handler in handlers) {
      try {
        handler(message);
      } catch (error) {
        print('❌ Ошибка обработчика: $error');
      }
    }
  }

  // ========================================
  // ПОДКЛЮЧЕНИЕ
  // ========================================

  Future<bool> connect(String url) async {
    _e2eeEnabled = await E2eeSettingsService.instance.isEnabled();
    if (_isConnected && _serverUrl == url && _channel != null) {
      return true;
    }

    _serverUrl = url;

    _manualDisconnect = false;

    _reconnectTimer?.cancel();

    _isReconnecting = false;

    connectionPhase.value = SpartanConnectionPhase.connecting;

    try {
      print('🔌 Подключение к серверу: $url');

      if (_channel != null) {
        try {
          await _channel!.sink.close();
        } catch (_) {}

        _channel = null;
      }

      final uri = Uri.parse(url);

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _handleRawMessage,
        onError: (Object error) {
          print('❌ Ошибка WebSocket: $error');

          _handleDisconnect(reason: 'Ошибка подключения к серверу');
        },
        onDone: () {
          print('🔴 WebSocket отключён');

          _handleDisconnect(reason: 'Соединение с сервером закрыто');
        },
        cancelOnError: false,
      );

      _isConnected = true;

      // Keep mobile WebSocket connections alive during quiet call periods.
      // Some Android vendors/NATs silently expire an otherwise idle socket.
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_isConnected && _channel != null) _send('ping', const {});
      });

      connectionPhase.value = SpartanConnectionPhase.authenticating;

      print('✅ WebSocket подключён');

      return true;
    } catch (error) {
      print('❌ Не удалось подключиться: $error');

      _isConnected = false;

      _channel = null;

      connectionPhase.value = SpartanConnectionPhase.disconnected;

      _scheduleReconnect();

      return false;
    }
  }

  // ========================================
  // ПОЛУЧЕНИЕ СООБЩЕНИЙ
  // ========================================

  Future<void> _handleRawMessage(dynamic rawMessage) async {
    try {
      final decoded = jsonDecode(rawMessage.toString());

      if (decoded is! Map) {
        return;
      }

      final message = Map<String, dynamic>.from(decoded);

      final type = message['type']?.toString() ?? '';

      final rawData = message['data'];

      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{};

      print('📨 ПОЛУЧЕНО: $type');

      // ======================================
      // УСПЕШНЫЙ ВХОД
      // ======================================

      if (type == 'login_success') {
        _authenticated = true;
        connectionPhase.value = SpartanConnectionPhase.connected;
        final username = data['username']?.toString();

        if (username != null && username.isNotEmpty) {
          currentUser = username;

          final mediaToken = data['mediaToken']?.toString().trim() ?? '';
          final mediaPort =
              int.tryParse(data['mediaPort']?.toString() ?? '') ?? 8081;
          final serverUrl = _serverUrl?.trim() ?? '';
          if (mediaToken.isNotEmpty && serverUrl.isNotEmpty) {
            MediaTransferService.configure(
              webSocketUrl: serverUrl,
              token: mediaToken,
              mediaPort: mediaPort,
            );
            print('📦 Медиа-сервер готов: порт $mediaPort');
          }

          print(
            '👤 Текущий пользователь: '
            '$currentUser',
          );

          _sendFcmToken();
          await SystemCallService.configure(serverUrl, username, mediaPort);

          if (_e2eeEnabled) {
            _e2eeActivePeers = await E2eeSettingsService.instance.activePeers(
              username,
            );
            await _prepareE2ee(username);
          } else {
            _e2eeActivePeers = <String>{};
            _send('e2ee_remove_bundle', const {});
          }

          if (_needsResyncAfterLogin) {
            _needsResyncAfterLogin = false;
            _receivingOfflineMessages = true;
            _send('get_offline_messages', const {});
            _send('get_groups', const {});
            _send('get_users', const {});
            print('🔄 RELAY: состояние после переподключения синхронизировано');
          }

          await _flushOutbox();
        }
      }

      // ======================================
      // ОФЛАЙН-СООБЩЕНИЯ ПОЛУЧЕНЫ
      // ======================================

      if (type == 'offline_messages_complete') {
        _receivingOfflineMessages = false;

        print('📭 Получение офлайн-сообщений завершено');
      }

      if (type == 'pinned_message_updated') {
        final user = currentUser?.trim() ?? '';
        final peer = data['peer']?.toString().trim() ?? '';
        final messageId = data['messageId']?.toString().trim() ?? '';
        if (user.isNotEmpty && peer.isNotEmpty && messageId.isNotEmpty) {
          if (data['pinned'] == true) {
            StorageService.addPinnedMessage(user, peer, {
              'messageId': messageId,
              'updatedAt': data['updatedAt']?.toString() ?? '',
            });
          } else {
            StorageService.removePinnedMessage(user, peer, messageId);
          }
          StorageService.updateMessagePinnedState(
            user,
            peer,
            messageId,
            data['pinned'] == true,
          );
        }
      }

      if (type == 'e2ee_prekey_bundle') {
        final username = data['username']?.toString().trim() ?? '';
        final request = _e2eeBundleRequests.remove(username);
        if (request != null && !request.isCompleted) {
          if (data['available'] == true) {
            try {
              await SignalE2eeService.instance.processRemoteBundle(
                username,
                data,
              );
              request.complete(data);
            } catch (error) {
              request.completeError(error);
            }
          } else {
            request.completeError(
              StateError(data['reason']?.toString() ?? 'E2EE keys unavailable'),
            );
          }
        }
        return;
      }

      if (type == 'e2ee_bundle_published') {
        final request = _e2eePublishRequest;
        _e2eePublishRequest = null;
        if (request != null && !request.isCompleted) {
          request.complete(data['ok'] == true);
        }
        return;
      }

      if (type == 'e2ee_invite_response') {
        final peer = data['from']?.toString().trim() ?? '';
        final accepted = data['accepted'] == true;
        final user = currentUser?.trim() ?? '';
        if (peer.isNotEmpty && user.isNotEmpty) {
          if (accepted) {
            _e2eeActivePeers.add(peer);
          } else {
            _e2eeActivePeers.remove(peer);
          }
          await E2eeSettingsService.instance.setPeerActive(
            user,
            peer,
            accepted,
          );
        }
      }

      if (type == 'e2ee_message_error') {
        final id = data['id']?.toString().trim() ?? '';
        final user = currentUser?.trim() ?? '';
        if (id.isNotEmpty && user.isNotEmpty) {
          _e2eeSendingIds.remove(id);
          StorageService.updateOutboxStatus(user, id, 'failed');
          final local = StorageService.getOutboxMessages(user)
              .where((item) => item['id']?.toString() == id)
              .cast<Map<String, dynamic>?>()
              .firstWhere((item) => item != null, orElse: () => null);
          _notifyHandlers({
            'type': 'outbox_failed',
            'data': {
              ...?local,
              'id': id,
              'status': 'failed',
              'reason':
                  data['reason']?.toString() ??
                  'Защищённое сообщение не отправлено',
            },
          });
        }
        return;
      }

      // ======================================
      // ВХОДЯЩЕЕ СООБЩЕНИЕ
      // ======================================

      if (type == 'message') {
        if (data['e2ee'] == true) {
          final from = data['from']?.toString().trim() ?? '';
          try {
            if (!_e2eeEnabled ||
                currentUser == null ||
                !_e2eeActivePeers.contains(from)) {
              throw StateError('E2EE is disabled on this device');
            }
            await SignalE2eeService.instance.initializeForUser(currentUser!);
            final decrypted = await SignalE2eeService.instance.decrypt(
              from,
              data,
            );
            final outerId = data['id']?.toString() ?? '';
            final outerTo = data['to']?.toString() ?? '';
            if (decrypted['id']?.toString() != outerId ||
                decrypted['from']?.toString() != from ||
                decrypted['to']?.toString() != outerTo) {
              throw const FormatException('E2EE envelope mismatch');
            }
            data
              ..addAll(decrypted)
              ..['e2ee'] = true
              ..['e2eeVersion'] = 2;
            message['data'] = data;
            if (data['cipherType'] == 3) {
              unawaited(_prepareE2ee(currentUser!));
            }
          } catch (error) {
            data
              ..['text'] = '🔒 Не удалось расшифровать сообщение'
              ..['e2eeError'] = true;
            message['data'] = data;
            print('🔒 E2EE: сообщение не расшифровано');
          }
        }
        final id = data['id']?.toString().trim() ?? '';

        final from = data['from']?.toString().trim() ?? '';

        final to = data['to']?.toString().trim() ?? '';

        final text = data['text']?.toString().trim() ?? '';

        final messageType =
            data['messageType']?.toString().trim().toLowerCase() ?? 'text';

        final voiceDurationMs = int.tryParse(
          data['voiceDurationMs']?.toString() ?? '',
        );

        final fileName = data['fileName']?.toString().trim();

        // Сообщение реально дошло до приложения.
        // Подтверждаем доставку серверу.
        if (id.isNotEmpty &&
            from.isNotEmpty &&
            to.isNotEmpty &&
            currentUser != null &&
            currentUser!.isNotEmpty &&
            to == currentUser &&
            from != currentUser) {
          sendMessageDelivered(messageId: id, from: from, to: to);
        }

        // Уведомление показываем только если:
        // 1. сообщение не от самого себя;
        // 2. это не повтор офлайн-сообщений;
        // 3. чат с этим человеком НЕ открыт.
        if (from.isNotEmpty &&
            text.isNotEmpty &&
            from != currentUser &&
            AppVisibility.shouldNotify(
              foreground: AppVisibility.instance.foreground,
              sameChat: from == _activeChatUser,
            ) &&
            !_receivingOfflineMessages) {
          unawaited(
            NotificationService.instance.showMessageNotification(
              from: from,
              message: text,
              messageType: messageType,
              voiceDurationMs: voiceDurationMs,
              fileName: fileName,
            ),
          );

          print(
            '🔔 Уведомление о сообщении: '
            '$from',
          );
        } else if (from.isNotEmpty && from == _activeChatUser) {
          print(
            '💬 Чат с $from открыт — '
            'уведомление не показываем',
          );
        }
      }

      // ======================================
      // ПОДТВЕРЖДЕНИЕ ДОСТАВКИ
      // ======================================

      if (type == 'message_delivered') {
        final messageId = data['messageId']?.toString().trim() ?? '';

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
        final messageId = data['messageId']?.toString().trim() ?? '';

        if (messageId.isNotEmpty) {
          print(
            '👁️ Сообщение прочитано: '
            '$messageId',
          );
        }
      }

      // ======================================
      // УВЕДОМЛЕНИЕ О СЕРДЕЧКЕ
      // ======================================

      if (type == 'group_message') {
        final groupId = data['groupId']?.toString() ?? '';
        final from = data['from']?.toString() ?? '';
        if (groupId.isNotEmpty &&
            from.isNotEmpty &&
            from != currentUser &&
            AppVisibility.shouldNotify(
              foreground: AppVisibility.instance.foreground,
              sameChat: activeGroupId == groupId,
            )) {
          unawaited(
            NotificationService.instance
                .showGroupMessageNotification(
                  groupId: groupId,
                  from: from,
                  message: data['text']?.toString() ?? 'Новое сообщение',
                )
                .catchError((Object error) {
                  print('Уведомление группы недоступно: $error');
                }),
          );
        }
      }

      if (type == 'reaction_update') {
        final changedBy = data['changedBy']?.toString().trim() ?? '';

        final reactionAdded = data['reactionAdded'] == true;

        if (reactionAdded && changedBy.isNotEmpty && changedBy != currentUser) {
          unawaited(
            NotificationService.instance.showReactionNotification(
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
        final username = data['username']?.toString() ?? '';

        final avatar = data['avatar']?.toString() ?? '';

        if (username.isNotEmpty) {
          if (avatar.isNotEmpty) {
            StorageService.saveAvatar(username, avatar);

            print(
              '🖼️ Аватарка получена и сохранена: '
              '$username',
            );
          } else {
            StorageService.removeAvatar(username);

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

      if (type == 'avatar_updated') {
        final username = data['username']?.toString() ?? '';

        if (username.isNotEmpty) {
          requestAvatar(username);
        }
      }

      // V621: медиа больше не декодируем в WebSocket-обработчике.
      // Сервер присылает только mediaId; загрузка выполняется лениво.

      if (type == 'message_sent') {
        final id = data['id']?.toString().trim() ?? '';
        final user = currentUser?.trim() ?? '';
        if (id.isNotEmpty && user.isNotEmpty) {
          _e2eeSendingIds.remove(id);
          if (data['e2ee'] == true) {
            final local = StorageService.getOutboxMessages(user)
                .where((item) => item['id']?.toString() == id)
                .cast<Map<String, dynamic>?>()
                .firstWhere((item) => item != null, orElse: () => null);
            if (local != null) {
              data
                ..['text'] = local['text']
                ..['replyTo'] = local['replyTo']
                ..['forwardedFrom'] = local['forwardedFrom']
                ..['forwardComment'] = local['forwardComment'];
              message['data'] = data;
            }
          }
          StorageService.removeOutboxMessage(user, id);
          _notifyHandlers({'type': 'outbox_sent', 'data': data});
        }
      }

      // ======================================
      // ПЕРЕДАЁМ СОБЫТИЕ ЭКРАНАМ
      // ======================================

      _notifyHandlers(message);
    } catch (error) {
      print('❌ Ошибка обработки сообщения: $error');
    }
  }

  // ========================================
  // FCM TOKEN
  // ========================================

  void _sendFcmToken() {
    final username = currentUser?.trim() ?? '';

    final token = FirebaseMessagingService.instance.token?.trim() ?? '';

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

    _send('register_fcm_token', {'token': token});

    print(
      '🔥 FCM token отправлен на сервер '
      'для $username',
    );
  }

  // ========================================
  // ПОТЕРЯ СОЕДИНЕНИЯ
  // ========================================

  void _handleDisconnect({required String reason}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isConnected = false;
    _authenticated = false;
    _e2eeSendingIds.clear();
    final publishRequest = _e2eePublishRequest;
    _e2eePublishRequest = null;
    if (publishRequest != null && !publishRequest.isCompleted) {
      publishRequest.complete(false);
    }
    for (final request in _e2eeBundleRequests.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('Соединение с сервером потеряно'));
      }
    }
    _e2eeBundleRequests.clear();

    _channel = null;

    _receivingOfflineMessages = false;

    _needsResyncAfterLogin = currentUser?.isNotEmpty == true;

    connectionPhase.value = SpartanConnectionPhase.disconnected;

    if (_manualDisconnect) {
      print(
        '⛔ Ручной выход. '
        'Переподключение запрещено.',
      );

      return;
    }

    _notifyHandlers({
      'type': 'disconnected',
      'data': {'reason': reason},
    });

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

    if (_serverUrl == null || _serverUrl!.isEmpty) {
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

    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      _isReconnecting = false;

      if (_manualDisconnect) {
        return;
      }

      final url = _serverUrl;

      final username = currentUser;

      final password = _lastPassword;

      if (url == null || username == null || password == null) {
        return;
      }

      print('🔄 Попытка переподключения...');

      connectionPhase.value = SpartanConnectionPhase.connecting;

      final connected = await connect(url);

      if (connected && !_manualDisconnect) {
        login(username, password);
      }
    });
  }

  // ========================================
  // ОТПРАВКА НА СЕРВЕР
  // ========================================

  bool _send(String type, Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print(
        '⚠️ Нет подключения. '
        'Не отправлено: $type',
      );

      return false;
    }

    final message = {'type': type, 'data': data};

    try {
      final json = jsonEncode(message);

      print('📤 Отправлено: $type');

      _channel!.sink.add(json);
      return true;
    } catch (error) {
      print('❌ Ошибка отправки: $error');
      return false;
    }
  }

  Future<void> _flushOutbox() async {
    final user = currentUser?.trim() ?? '';
    if (_flushingOutbox || user.isEmpty || !_isConnected || _channel == null) {
      return;
    }
    _flushingOutbox = true;
    try {
      final queued = StorageService.getOutboxMessages(user);
      for (final item in queued) {
        if (!_isConnected || _channel == null) break;
        final id = item['id']?.toString().trim() ?? '';
        final target = item['to']?.toString().trim() ?? '';
        if (id.isEmpty || target.isEmpty) continue;
        StorageService.updateOutboxStatus(user, id, 'sending');
        _notifyHandlers({'type': 'outbox_sending', 'data': item});
        if (item['requiresE2ee'] == true) {
          unawaited(_sendE2eeMessage(Map<String, dynamic>.from(item)));
          continue;
        }
        final payload = Map<String, dynamic>.from(item)
          ..remove('from')
          ..remove('isMe')
          ..remove('status');
        if (!_send('message', payload)) {
          StorageService.updateOutboxStatus(user, id, 'queued');
          break;
        }
      }
    } finally {
      _flushingOutbox = false;
    }
  }

  // ========================================
  // РЕГИСТРАЦИЯ
  // ========================================

  void register(String username, String password) {
    _send('register', {'username': username.trim(), 'password': password});
  }

  // ========================================
  // ВХОД
  // ========================================

  void login(String username, String password) {
    final user = username.trim();

    if (user.isEmpty || password.isEmpty) {
      return;
    }

    _manualDisconnect = false;

    currentUser = user;

    _lastPassword = password;

    connectionPhase.value = SpartanConnectionPhase.authenticating;

    _send('login', {'username': user, 'password': password});
  }

  // ========================================
  // ПОЛЬЗОВАТЕЛИ
  // ========================================

  void getUsers() {
    _send('get_users', {});
  }
  // ========================================
  // GROUPS — STAGE 24
  // SPARTAN_STAGE24_GROUPS
  // ========================================

  void getRegisteredUsers() {
    _send('get_registered_users', {});
  }

  void getGroups() {
    _send('get_groups', {});
  }

  void createGroup(String name, List<String> members) {
    final groupName = name.trim();
    final cleanMembers = members
        .map((user) => user.trim())
        .where((user) => user.isNotEmpty)
        .toSet()
        .toList();

    if (groupName.isEmpty || cleanMembers.isEmpty) {
      return;
    }

    _send('create_group', {'name': groupName, 'members': cleanMembers});
  }

  // SPARTAN_STAGE24_1_ADD_MEMBERS
  void addGroupMembers(String groupId, List<String> members) {
    final id = groupId.trim();
    final cleanMembers = members
        .map((user) => user.trim())
        .where((user) => user.isNotEmpty)
        .toSet()
        .toList();

    if (id.isEmpty || cleanMembers.isEmpty) {
      return;
    }

    _send('add_group_members', {'groupId': id, 'members': cleanMembers});
  }

  // ========================================
  // GROUP MESSAGES - STAGE 25
  // SPARTAN_STAGE25_GROUP_MESSAGES
  // ========================================

  void getGroupMessages(String groupId, {String? before, int limit = 60}) {
    final id = groupId.trim();
    if (id.isEmpty) return;

    final data = <String, dynamic>{
      'groupId': id,
      'limit': limit.clamp(20, 100),
    };
    final cursor = before?.trim() ?? '';
    if (cursor.isNotEmpty) data['before'] = cursor;

    _send('get_group_messages', data);
  }

  // ========================================
  // GROUP TYPING - STAGE 30
  // ========================================

  void sendGroupTyping(String groupId, bool isTyping) {
    final id = groupId.trim();

    if (id.isEmpty) {
      return;
    }

    final user = currentUser?.trim() ?? '';

    if (user.isEmpty) {
      return;
    }

    _send('group_typing', {'groupId': id, 'isTyping': isTyping});
  }

  void sendGroupMessage(
    String groupId,
    String text, {
    Map<String, dynamic>? replyTo,
  }) {
    final id = groupId.trim();

    final messageText = text.trim();

    if (id.isEmpty || messageText.isEmpty) {
      return;
    }

    final data = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'groupId': id,
      'text': messageText,
      'time': DateTime.now().toIso8601String(),
    };

    if (replyTo != null) {
      data['replyTo'] = Map<String, dynamic>.from(replyTo);
    }

    _send('group_message', data);
  }

  // ========================================
  // GROUP MEDIA - STAGE 28
  // SPARTAN_STAGE28_GROUP_MEDIA
  // ========================================

  void sendGroupMediaMessage(
    String groupId, {
    required String messageType,
    required String mediaId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String text,
    int? voiceDurationMs,
    Map<String, dynamic>? replyTo,
  }) {
    final id = groupId.trim();
    final type = messageType.trim().toLowerCase();
    final remoteId = mediaId.trim();
    final name = fileName.trim();
    final mediaMime = mimeType.trim();
    final label = text.trim();

    const supported = <String>{'image', 'video', 'file', 'voice'};
    if (id.isEmpty ||
        !supported.contains(type) ||
        remoteId.isEmpty ||
        name.isEmpty ||
        fileSize <= 0) {
      return;
    }

    final data = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'groupId': id,
      'text': label.isEmpty ? '📎 Вложение' : label,
      'time': DateTime.now().toIso8601String(),
      'messageType': type,
      'mediaId': remoteId,
      'fileName': name,
      'fileSize': fileSize,
      'mimeType': mediaMime,
    };

    if (type == 'voice' && voiceDurationMs != null && voiceDurationMs > 0) {
      data['voiceDurationMs'] = voiceDurationMs;
    }
    if (replyTo != null) {
      data['replyTo'] = Map<String, dynamic>.from(replyTo);
    }
    _send('group_message', data);
  }

  // ========================================
  // GROUP MESSAGE ACTIONS - STAGE 26
  // SPARTAN_STAGE26_GROUP_ACTIONS
  // ========================================

  void editGroupMessage({
    required String groupId,
    required String messageId,
    required String text,
  }) {
    final id = groupId.trim();
    final targetMessageId = messageId.trim();
    final messageText = text.trim();

    if (id.isEmpty || targetMessageId.isEmpty || messageText.isEmpty) {
      return;
    }

    _send('group_edit_message', {
      'groupId': id,
      'messageId': targetMessageId,
      'text': messageText,
    });
  }

  void deleteGroupMessage({
    required String groupId,
    required String messageId,
  }) {
    final id = groupId.trim();
    final targetMessageId = messageId.trim();

    if (id.isEmpty || targetMessageId.isEmpty) {
      return;
    }

    _send('group_delete_message', {
      'groupId': id,
      'messageId': targetMessageId,
    });
  }

  void sendGroupReaction({
    required String groupId,
    required String messageId,
    required String reaction,
  }) {
    final id = groupId.trim();
    final targetMessageId = messageId.trim();
    final reactionValue = reaction.trim();

    if (id.isEmpty || targetMessageId.isEmpty || reactionValue.isEmpty) {
      return;
    }

    _send('group_reaction', {
      'groupId': id,
      'messageId': targetMessageId,
      'reaction': reactionValue,
    });
  }

  // ========================================
  // ОФЛАЙН-СООБЩЕНИЯ
  // ========================================

  void getOfflineMessages() {
    _receivingOfflineMessages = true;

    _send('get_offline_messages', {});
  }

  // ========================================
  // СТАТУС КОНТАКТА / LAST SEEN
  // ========================================

  void getUserStatus(String username) {
    final user = username.trim();

    if (user.isEmpty) {
      return;
    }

    _send('get_user_status', {'username': user});
  }

  // ========================================
  // ПЕЧАТАЕТ / TYPING
  // ========================================

  void sendTyping(String to, bool isTyping) {
    final target = to.trim();

    if (target.isEmpty) {
      return;
    }

    if (currentUser == null || currentUser!.isEmpty) {
      return;
    }

    _send('typing', {'to': target, 'isTyping': isTyping});
  }

  // ========================================
  // СООБЩЕНИЕ
  // ========================================

  String sendMessage(
    String to,
    String text, {
    Map<String, dynamic>? replyTo,
    String? forwardedFrom,
    String? forwardComment,
  }) {
    final target = to.trim();

    final messageText = text.trim();

    if (target.isEmpty || messageText.isEmpty) {
      return '';
    }

    final messageData = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'from': currentUser ?? '',
      'to': target,
      'text': messageText,
      'time': DateTime.now().toIso8601String(),
    };

    if (replyTo != null) {
      final replyId = replyTo['id']?.toString().trim() ?? '';

      final replyFrom = replyTo['from']?.toString().trim() ?? '';

      final replyText = replyTo['text']?.toString().trim() ?? '';

      if (replyId.isNotEmpty && replyFrom.isNotEmpty && replyText.isNotEmpty) {
        messageData['replyTo'] = {
          'id': replyId,
          'from': replyFrom,
          'text': replyText,
        };
      }
    }

    final originalAuthor = forwardedFrom?.trim() ?? '';

    if (originalAuthor.isNotEmpty) {
      messageData['forwardedFrom'] = originalAuthor;
    }

    final comment = forwardComment?.trim() ?? '';

    if (comment.isNotEmpty) {
      messageData['forwardComment'] = comment;
    }

    final user = currentUser?.trim() ?? '';
    final connected = _isConnected && _channel != null;
    final protectWithE2ee = isE2eeActiveWith(target);
    if (protectWithE2ee) {
      messageData['requiresE2ee'] = true;
      messageData['e2ee'] = true;
    }
    if (user.isNotEmpty) {
      messageData['status'] = connected ? 'sending' : 'queued';
      messageData['isMe'] = true;
      StorageService.saveOutboxMessage(user, messageData);
      _notifyHandlers({
        'type': connected ? 'outbox_sending' : 'outbox_queued',
        'data': messageData,
      });
    }

    if (protectWithE2ee && user.isNotEmpty) {
      if (connected) {
        unawaited(_sendE2eeMessage(Map<String, dynamic>.from(messageData)));
      }
      return messageData['id'].toString();
    }

    final payload = Map<String, dynamic>.from(messageData)
      ..remove('isMe')
      ..remove('status');
    if (!_send('message', payload) && user.isNotEmpty) {
      StorageService.updateOutboxStatus(
        user,
        messageData['id'].toString(),
        'queued',
      );
      _notifyHandlers({'type': 'outbox_queued', 'data': messageData});
    }
    return messageData['id'].toString();
  }

  Future<bool> setE2eeEnabled(bool enabled) async {
    final user = currentUser?.trim() ?? '';
    if (enabled && user.isNotEmpty && isAuthenticated) {
      final ready = await _prepareE2ee(user);
      if (!ready) return false;
    } else if (!enabled && isAuthenticated) {
      for (final peer in _e2eeActivePeers) {
        _send('e2ee_invite_response', {
          'to': peer,
          'accepted': false,
          'disabled': true,
        });
      }
      _send('e2ee_remove_bundle', const {});
    }
    await E2eeSettingsService.instance.setEnabled(enabled);
    _e2eeEnabled = enabled;
    if (!enabled) {
      _e2eeActivePeers = <String>{};
      await E2eeSettingsService.instance.clearActivePeers(user);
    }
    return true;
  }

  Future<bool> inviteE2ee(String username) async {
    final peer = username.trim();
    if (peer.isEmpty || !isAuthenticated) return false;
    if (!_e2eeEnabled && !await setE2eeEnabled(true)) return false;
    return _send('e2ee_invite', {'to': peer});
  }

  Future<bool> respondToE2eeInvite(String username, bool accepted) async {
    final peer = username.trim();
    final user = currentUser?.trim() ?? '';
    if (peer.isEmpty || user.isEmpty || !isAuthenticated) return false;
    if (accepted && !_e2eeEnabled && !await setE2eeEnabled(true)) {
      return false;
    }
    final sent = _send('e2ee_invite_response', {
      'to': peer,
      'accepted': accepted,
    });
    if (!sent && accepted) return false;
    if (accepted) {
      _e2eeActivePeers.add(peer);
    } else {
      _e2eeActivePeers.remove(peer);
    }
    await E2eeSettingsService.instance.setPeerActive(user, peer, accepted);
    return sent || !accepted;
  }

  Future<bool> _prepareE2ee(String username) async {
    try {
      await SignalE2eeService.instance.initializeForUser(username);
      final bundle = await SignalE2eeService.instance.createPublicBundle();
      final previous = _e2eePublishRequest;
      if (previous != null && !previous.isCompleted) {
        previous.complete(false);
      }
      final request = Completer<bool>();
      _e2eePublishRequest = request;
      if (!_send('e2ee_publish_bundle', bundle)) {
        _e2eePublishRequest = null;
        throw StateError('E2EE server unavailable');
      }
      final accepted = await request.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (identical(_e2eePublishRequest, request)) {
            _e2eePublishRequest = null;
          }
          return false;
        },
      );
      if (!accepted) throw StateError('E2EE bundle rejected');
      print('🔐 Signal E2EE готов');
      return true;
    } catch (error) {
      print('🔒 E2EE не удалось подготовить: $error');
      _notifyHandlers({
        'type': 'e2ee_status',
        'data': {'ready': false, 'reason': 'Не удалось подготовить E2EE'},
      });
      return false;
    }
  }

  Future<void> _requestE2eeBundle(String username) async {
    final existing = _e2eeBundleRequests[username];
    if (existing != null) {
      await existing.future;
      return;
    }
    final completer = Completer<Map<String, dynamic>>();
    _e2eeBundleRequests[username] = completer;
    if (!_send('e2ee_get_bundle', {'username': username})) {
      _e2eeBundleRequests.remove(username);
      throw StateError('Нет соединения с сервером');
    }
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _e2eeBundleRequests.remove(username);
        throw TimeoutException('E2EE key request timed out');
      },
    );
  }

  Future<void> _sendE2eeMessage(Map<String, dynamic> localMessage) async {
    final user = currentUser?.trim() ?? '';
    final id = localMessage['id']?.toString().trim() ?? '';
    final target = localMessage['to']?.toString().trim() ?? '';
    if (user.isEmpty || id.isEmpty || target.isEmpty) return;
    if (!_e2eeSendingIds.add(id)) return;
    try {
      await SignalE2eeService.instance.initializeForUser(user);
      Map<String, dynamic> encrypted;
      try {
        encrypted = await SignalE2eeService.instance.encrypt(
          target,
          _privateE2eePayload(localMessage, user),
        );
      } on E2eeSessionMissing {
        await _requestE2eeBundle(target);
        encrypted = await SignalE2eeService.instance.encrypt(
          target,
          _privateE2eePayload(localMessage, user),
        );
      }
      final envelope = <String, dynamic>{
        'id': id,
        'to': target,
        'time': localMessage['time'],
        ...encrypted,
      };
      if (!_send('e2ee_message', envelope)) {
        throw StateError('Нет соединения с сервером');
      }
    } catch (error) {
      _e2eeSendingIds.remove(id);
      StorageService.updateOutboxStatus(user, id, 'failed');
      _notifyHandlers({
        'type': 'outbox_failed',
        'data': {
          ...localMessage,
          'status': 'failed',
          'reason': 'Контакт ещё не готов к защищённой переписке',
        },
      });
      print('🔒 E2EE: сообщение не отправлено');
    }
  }

  Map<String, dynamic> _privateE2eePayload(
    Map<String, dynamic> message,
    String from,
  ) => {
    'id': message['id'],
    'from': from,
    'to': message['to'],
    'text': message['text'],
    'time': message['time'],
    if (message['replyTo'] is Map) 'replyTo': message['replyTo'],
    if (message['forwardedFrom'] != null)
      'forwardedFrom': message['forwardedFrom'],
    if (message['forwardComment'] != null)
      'forwardComment': message['forwardComment'],
  };

  // ========================================
  // STAGE 29 - PRIVATE MEDIA
  // ========================================

  void sendMediaMessage(
    String to, {
    required String messageType,
    required String mediaId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String text,
    Map<String, dynamic>? replyTo,
    String? forwardedFrom,
    String? forwardComment,
  }) {
    final target = to.trim();
    final type = messageType.trim().toLowerCase();
    final remoteId = mediaId.trim();
    final name = fileName.trim();
    final mime = mimeType.trim();
    final label = text.trim();

    const supported = <String>{'image', 'video', 'file'};
    if (target.isEmpty ||
        !supported.contains(type) ||
        remoteId.isEmpty ||
        name.isEmpty ||
        fileSize <= 0) {
      return;
    }

    final data = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'to': target,
      'text': label.isEmpty ? '📎 Вложение' : label,
      'time': DateTime.now().toIso8601String(),
      'messageType': type,
      'mediaId': remoteId,
      'fileName': name,
      'fileSize': fileSize,
      'mimeType': mime,
    };

    if (replyTo != null) {
      final replyId = replyTo['id']?.toString().trim() ?? '';
      final replyFrom = replyTo['from']?.toString().trim() ?? '';
      final replyText = replyTo['text']?.toString().trim() ?? '';
      if (replyId.isNotEmpty && replyFrom.isNotEmpty && replyText.isNotEmpty) {
        data['replyTo'] = {'id': replyId, 'from': replyFrom, 'text': replyText};
      }
    }
    final originalAuthor = forwardedFrom?.trim() ?? '';
    if (originalAuthor.isNotEmpty) {
      data['forwardedFrom'] = originalAuthor;
    }
    final comment = forwardComment?.trim() ?? '';
    if (comment.isNotEmpty) {
      data['forwardComment'] = comment;
    }
    _send('media_message', data);
  }

  // ========================================
  // V621 — ГОЛОСОВОЕ ЧЕРЕЗ MEDIA STORAGE
  // ========================================

  void sendVoiceMessage(
    String to, {
    required String mediaId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required int durationMs,
    Map<String, dynamic>? replyTo,
    String? forwardedFrom,
    String? forwardComment,
  }) {
    final target = to.trim();
    final remoteId = mediaId.trim();
    if (target.isEmpty ||
        remoteId.isEmpty ||
        durationMs <= 0 ||
        fileSize <= 0) {
      return;
    }

    final messageData = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'to': target,
      'text':
          '🎙️ Голосовое сообщение · ${durationMs ~/ 60000}:${((durationMs ~/ 1000) % 60).toString().padLeft(2, '0')}',
      'time': DateTime.now().toIso8601String(),
      'messageType': 'voice',
      'mediaId': remoteId,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'voiceDurationMs': durationMs,
      'voiceMimeType': mimeType,
    };

    if (replyTo != null) {
      final replyId = replyTo['id']?.toString().trim() ?? '';
      final replyFrom = replyTo['from']?.toString().trim() ?? '';
      final replyText = replyTo['text']?.toString().trim() ?? '';
      if (replyId.isNotEmpty && replyFrom.isNotEmpty && replyText.isNotEmpty) {
        messageData['replyTo'] = {
          'id': replyId,
          'from': replyFrom,
          'text': replyText,
        };
      }
    }

    final originalAuthor = forwardedFrom?.trim() ?? '';
    if (originalAuthor.isNotEmpty) {
      messageData['forwardedFrom'] = originalAuthor;
    }
    final comment = forwardComment?.trim() ?? '';
    if (comment.isNotEmpty) {
      messageData['forwardComment'] = comment;
    }

    _send('message', messageData);
  }

  // ========================================
  // РЕДАКТИРОВАНИЕ СООБЩЕНИЯ
  // ========================================

  void editMessage({
    required String messageId,
    required String to,
    required String newText,
  }) {
    final id = messageId.trim();

    final target = to.trim();

    final text = newText.trim();

    if (id.isEmpty || target.isEmpty || text.isEmpty) {
      return;
    }

    _send('edit_message', {'messageId': id, 'to': target, 'newText': text});
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

    if (id.isEmpty || target.isEmpty) {
      return;
    }

    _send('delete_message_for_everyone', {'messageId': id, 'to': target});
  }

  // ========================================
  // СООБЩЕНИЕ ДОСТАВЛЕНО
  // ========================================

  void sendMessageDelivered({
    required String messageId,
    required String from,
    required String to,
  }) {
    final id = messageId.trim();

    final messageFrom = from.trim();

    final messageTo = to.trim();

    if (id.isEmpty || messageFrom.isEmpty || messageTo.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty ||
        currentUser != messageTo) {
      return;
    }

    _send('message_delivered', {
      'messageId': id,
      'from': messageFrom,
      'to': messageTo,
    });
  }

  // ========================================
  // СООБЩЕНИЕ ПРОЧИТАНО
  // ========================================

  void sendMessageRead({
    required String messageId,
    required String from,
    required String to,
  }) {
    final id = messageId.trim();

    final messageFrom = from.trim();

    final messageTo = to.trim();

    if (id.isEmpty || messageFrom.isEmpty || messageTo.isEmpty) {
      return;
    }

    if (currentUser == null ||
        currentUser!.isEmpty ||
        currentUser != messageTo) {
      return;
    }

    _send('message_read', {
      'messageId': id,
      'from': messageFrom,
      'to': messageTo,
    });
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
    final id = messageId.trim();

    final messageFrom = from.trim();

    final messageTo = to.trim();

    final reactionValue = reaction.trim();

    if (id.isEmpty ||
        messageFrom.isEmpty ||
        messageTo.isEmpty ||
        reactionValue.isEmpty) {
      return;
    }

    _send('message_reaction', {
      'messageId': id,
      'from': messageFrom,
      'to': messageTo,
      'reaction': reactionValue,
    });
  }

  // ========================================
  // ЗАГРУЗКА АВАТАРКИ
  // ========================================

  Future<void> setAvatarFromPath(String path) async {
    try {
      if (currentUser == null || currentUser!.isEmpty) {
        print('⚠️ Пользователь не авторизован');

        return;
      }

      final file = File(path);

      if (!await file.exists()) {
        print(
          '❌ Файл аватарки не найден: '
          '$path',
        );

        return;
      }

      final bytes = await file.readAsBytes();

      final avatarBase64 = base64Encode(bytes);

      StorageService.saveAvatar(currentUser!, avatarBase64);

      _send('upload_avatar', {'avatar': avatarBase64});

      print('🖼️ Аватарка отправлена на сервер');
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

  void requestAvatar(String username) {
    final user = username.trim();

    if (user.isEmpty) {
      return;
    }

    _send('get_avatar', {'username': user});
  }

  // ========================================
  // УДАЛЕНИЕ АВАТАРКИ
  // ========================================

  Future<void> deleteAvatar() async {
    final username = currentUser;

    if (username == null || username.isEmpty) {
      return;
    }

    _send('delete_avatar', {});

    await StorageService.removeAvatar(username);

    print('🗑️ Аватарка удалена');
  }

  // ========================================
  // CHATGPT
  // ========================================

  void sendChatGptRequest({
    required String requestId,
    required String action,
    required String text,
  }) {
    final id = requestId.trim();
    final cleanAction = action.trim();
    final cleanText = text.trim();

    if (id.isEmpty || cleanAction.isEmpty || cleanText.isEmpty) {
      return;
    }

    _send('chatgpt_request', {
      'requestId': id,
      'action': cleanAction,
      'text': cleanText,
    });
  }

  // ========================================
  // SPARTAN AI
  // ========================================

  void requestSpartanAiHistory({required String requestId}) {
    final id = requestId.trim();

    if (id.isEmpty) {
      return;
    }

    _send('get_spartan_ai_history', {'requestId': id});
  }

  void sendSpartanAiRequest({
    required String requestId,
    required String text,
    String? peer,
  }) {
    final id = requestId.trim();
    final cleanText = text.trim();
    final cleanPeer = peer?.trim() ?? '';

    if (id.isEmpty || cleanText.isEmpty) {
      return;
    }

    _send('spartan_ai_request', {
      'requestId': id,
      'text': cleanText,
      'peer': cleanPeer,
    });
  }

  void clearSpartanAiHistory({required String requestId}) {
    final id = requestId.trim();

    if (id.isEmpty) {
      return;
    }

    _send('clear_spartan_ai_history', {'requestId': id});
  }

  // ========================================
  // CHATGPT AUTO REPLY
  // ========================================

  void requestAutoReplySettings(String peer) {
    final target = peer.trim();

    if (target.isEmpty) {
      return;
    }

    _send('get_auto_reply_settings', {'peer': target});
  }

  void setAutoReplySettings({
    required String peer,
    required bool enabled,
    required String mode,
    required int idleSeconds,
    required String goal,
    required String prompt,
    required String context,
    required String boundaries,
    required int delaySeconds,
  }) {
    final target = peer.trim();

    if (target.isEmpty) {
      return;
    }

    _send('set_auto_reply_settings', {
      'peer': target,
      'enabled': enabled,
      'mode': mode.trim(),
      'idleSeconds': idleSeconds,
      'goal': goal.trim(),
      'prompt': prompt.trim(),
      'context': context.trim(),
      'boundaries': boundaries.trim(),
      'delaySeconds': delaySeconds,
    });
  }

  void clearAutoReplyHistory(String peer) {
    final target = peer.trim();

    if (target.isEmpty) {
      return;
    }

    _send('clear_auto_reply_history', {'peer': target});
  }

  // ========================================
  // PRIVATE AUDIO / VIDEO CALL SIGNALING
  // ========================================

  void requestPendingCall([String? callId]) =>
      _send('get_pending_call', {'callId': callId ?? ''});
  void sendGroupCall(String type, Map<String, dynamic> data) =>
      _send(type, data);
  void sendPulse(String type, Map<String, dynamic> data) => _send(type, data);
  void sendCallConnected({required String to, required String callId}) =>
      _send('call_connected', {'to': to, 'callId': callId});

  void sendCallOffer({
    required String to,
    required String callId,
    required bool video,
    required Map<String, dynamic> sdp,
  }) {
    _send('call_offer', {
      'to': to.trim(),
      'callId': callId.trim(),
      'video': video,
      'sdp': sdp,
    });
  }

  void sendCallAnswer({
    required String to,
    required String callId,
    required Map<String, dynamic> sdp,
  }) {
    _send('call_answer', {
      'to': to.trim(),
      'callId': callId.trim(),
      'sdp': sdp,
    });
  }

  void sendCallIceCandidate({
    required String to,
    required String callId,
    required Map<String, dynamic> candidate,
  }) {
    _send('call_ice_candidate', {
      'to': to.trim(),
      'callId': callId.trim(),
      'candidate': candidate,
    });
  }

  void sendCallReject({
    required String to,
    required String callId,
    String reason = 'declined',
  }) {
    _send('call_reject', {
      'to': to.trim(),
      'callId': callId.trim(),
      'reason': reason.trim(),
    });
  }

  void sendCallEnd({required String to, required String callId}) {
    _send('call_end', {'to': to.trim(), 'callId': callId.trim()});
  }

  // ========================================
  // РУЧНОЙ ВЫХОД
  // ========================================

  Future<void> disconnect({bool clearUser = true}) async {
    _manualDisconnect = true;
    _notifyHandlers({
      'type': 'disconnected',
      'data': {'reason': 'Выход из приложения'},
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _isReconnecting = false;

    _receivingOfflineMessages = false;

    _needsResyncAfterLogin = false;

    connectionPhase.value = SpartanConnectionPhase.disconnected;

    final channel = _channel;

    if (clearUser) {
      _authenticated = false;
      await SystemCallService.clearAccount();
      activeGroupId = null;
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

  // ========================================
  // PIN / UNPIN MESSAGE
  // ========================================

  void setPinnedMessage({
    required String messageId,
    required String to,
    required bool pinned,
    String messageFrom = '',
  }) {
    final id = messageId.trim();
    final target = to.trim();

    if (id.isEmpty || target.isEmpty) {
      return;
    }

    _send(pinned ? 'pin_message' : 'unpin_message', {
      'messageId': id,
      'to': target,
      'messageFrom': messageFrom.trim(),
    });
  }
}
