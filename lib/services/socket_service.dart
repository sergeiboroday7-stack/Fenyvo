import 'package:fenyvo/services/crypto/private_e2ee_edit_protocol.dart';

import 'dart:math';

import 'package:fenyvo/services/crypto/private_e2ee_edit_delivery_policy.dart';

import 'crypto/e2ee_inbound_policy.dart';
import 'crypto/e2ee_delivery_policy.dart';
import 'socket_login_continuation_guard.dart';
import 'socket_event_generation_guard.dart';
import '../features/messages/domain/message_id_generator.dart';

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
import 'turn_credential_service.dart';
import 'e2ee_settings_service.dart';
import 'crypto/signal_e2ee_service.dart';

enum FenyvoConnectionPhase {
  disconnected,
  connecting,
  authenticating,
  connected,
}

class SocketService {
  // null means the server did not provide recovery status.
  bool? recoveryConfigured;
  static final SocketService _instance = SocketService._internal();

  static SocketService get instance => _instance;

  SocketService._internal() {
    AppVisibility.instance.changes.addListener(_syncPresence);
  }

  void _syncPresence() {
    if (!_authenticated || !_isConnected || _channel == null) {
      return;
    }

    final active = AppVisibility.instance.foreground;
    print('[PRESENCE_SEND] foreground=$active');
    _send('presence_update', <String, dynamic>{'foreground': active});
  }

  WebSocketChannel? _channel;
  int _connectionGeneration = 0;

  final List<void Function(Map<String, dynamic>)> _messageHandlers = [];

  final Map<String, Map<String, dynamic>> _communicationStates =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _userProfiles =
      <String, Map<String, dynamic>>{};

  String? currentUser;

  String? _activeChatUser;
  String? activeGroupId;
  void registerCurrentFcmToken() => _sendFcmToken();

  bool _isConnected = false;
  bool _authenticated = false;
  bool get isAuthenticated => _isConnected && _authenticated;

  final ValueNotifier<FenyvoConnectionPhase> connectionPhase =
      ValueNotifier<FenyvoConnectionPhase>(FenyvoConnectionPhase.disconnected);

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
  final Set<String> _e2eeRecoveryPeers = <String>{};
  // Limits repeated recovery attempts without changing Signal identities.
  final Map<String, DateTime> _e2eeRecoveryAttempts = <String, DateTime>{};
  Completer<bool>? _e2eePublishRequest;

  bool get e2eeEnabled => _e2eeEnabled;

  bool isE2eeActiveWith(String username) =>
      _e2eeEnabled && _e2eeActivePeers.contains(username.trim());

  Future<bool> isE2eeReadyWith(String username) async {
    final user = currentUser?.trim() ?? '';
    final peer = username.trim();

    if (user.isEmpty || peer.isEmpty) return false;
    if (_e2eeActivePeers.contains(peer)) return true;

    // Capture the account and the active transport before loading.
    // Preferences may complete after logout or reconnection.
    final readGeneration = _connectionGeneration;
    final readChannel = _channel;

    final stored = await E2eeSettingsService.instance.activePeers(user);

    if (currentUser?.trim() != user ||
        !isAuthenticated ||
        !SocketEventGenerationGuard.isCurrent(
          eventGeneration: readGeneration,
          currentGeneration: _connectionGeneration,
          eventChannel: readChannel,
          currentChannel: _channel,
        )) {
      return false;
    }

    _e2eeActivePeers = stored;
    return stored.contains(peer);
  }

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

    connectionPhase.value = FenyvoConnectionPhase.connecting;

    try {
      print('🔌 Подключение к серверу: $url');

      if (_channel != null) {
        try {
          await _channel!.sink.close();
        } catch (_) {}

        _channel = null;
      }

      final uri = Uri.parse(url);

      final generation = ++_connectionGeneration;
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      channel.stream.listen(
        (rawMessage) {
          if (!SocketEventGenerationGuard.isCurrent(
            eventGeneration: generation,
            currentGeneration: _connectionGeneration,
            eventChannel: channel,
            currentChannel: _channel,
          )) {
            return;
          }

          unawaited(
            _handleRawMessage(
              rawMessage,
              generation: generation,
              channel: channel,
            ),
          );
        },
        onError: (Object error) {
          print('❌ Ошибка WebSocket: $error');

          _handleDisconnect(
            reason: 'Ошибка подключения к серверу',
            generation: generation,
            channel: channel,
          );
        },
        onDone: () {
          print('🔴 WebSocket отключён');

          _handleDisconnect(
            reason: 'Соединение с сервером закрыто',
            generation: generation,
            channel: channel,
          );
        },
        cancelOnError: false,
      );

      await channel.ready;
      if (_connectionGeneration != generation || !identical(_channel, channel))
        return false;
      _isConnected = true;

      // Keep mobile WebSocket connections alive during quiet call periods.
      // Some Android vendors/NATs silently expire an otherwise idle socket.
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_isConnected && _channel != null) {
          _send('ping', const {});

          if (_authenticated && AppVisibility.instance.foreground) {
            _syncPresence();
          }
        }
      });

      connectionPhase.value = FenyvoConnectionPhase.authenticating;

      print('✅ WebSocket подключён');

      return true;
    } catch (error) {
      print('❌ Не удалось подключиться: $error');

      _isConnected = false;

      _channel = null;

      connectionPhase.value = FenyvoConnectionPhase.disconnected;

      _scheduleReconnect();

      return false;
    }
  }

  // ========================================
  // ПОЛУЧЕНИЕ СООБЩЕНИЙ
  // ========================================

  Future<void> _handleRawMessage(
    dynamic rawMessage, {
    required int generation,
    required WebSocketChannel channel,
  }) async {
    if (!SocketEventGenerationGuard.isCurrent(
      eventGeneration: generation,
      currentGeneration: _connectionGeneration,
      eventChannel: channel,
      currentChannel: _channel,
    )) {
      return;
    }

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
        recoveryConfigured = data['recoveryConfigured'] is bool
            ? data['recoveryConfigured'] as bool
            : null;
        connectionPhase.value = FenyvoConnectionPhase.connected;
        final username = data['username']?.toString();

        if (username != null && username.isNotEmpty) {
          currentUser = username;

          // Reject an obsolete login continuation after an await.
          bool loginStillCurrent() {
            return SocketLoginContinuationGuard.isCurrent(
              eventGeneration: generation,
              currentGeneration: _connectionGeneration,
              eventChannel: channel,
              currentChannel: _channel,
              isAuthenticated: _authenticated,
              expectedOwner: username,
              activeOwner: currentUser,
            );
          }

          if (!loginStillCurrent()) return;
          _syncPresence();

          // Authentication is already complete. Let the UI continue before
          // platform and Signal bootstrap so secure-store/network latency does
          // not make a valid login appear frozen.
          _notifyHandlers(message);

          final mediaToken = data['mediaToken']?.toString().trim() ?? '';
          final mediaPort =
              int.tryParse(data['mediaPort']?.toString() ?? '') ?? 8081;
          final serverUrl = _serverUrl?.trim() ?? '';
          final turnData = data['turn'];
          TurnCredentialService.configure(
            turnData is Map ? Map<String, dynamic>.from(turnData) : null,
          );
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

          if (!loginStillCurrent()) return;
          _sendFcmToken();

          await SystemCallService.configure(serverUrl, username, mediaPort);

          // The user might have logged out during call initialization.
          if (!loginStillCurrent()) return;

          // Mandatory Signal E2EE. Preserve existing sessions.
          _e2eeEnabled = true;
          await E2eeSettingsService.instance.setEnabled(true);
          if (!loginStillCurrent()) return;

          final loginPeers = await E2eeSettingsService.instance.activePeers(
            username,
          );
          if (!loginStillCurrent()) return;
          _e2eeActivePeers = loginPeers;

          // Authentication must not wait for crypto bootstrap. Publishing the
          // Signal bundle can legitimately take several seconds (or time out
          // while the server is recovering), but the accepted login and the
          // initial state sync must remain responsive. Private delivery still
          // fails closed: the outbox is flushed only after E2EE is ready.
          unawaited(() async {
            final ready = await _prepareE2ee(username);
            if (!ready || !loginStillCurrent()) return;
            await _flushOutbox();
          }());

          if (_needsResyncAfterLogin) {
            _needsResyncAfterLogin = false;
            _receivingOfflineMessages = true;
            _send('get_offline_messages', const {});
            _send('get_communication_requests', const {});
            _send('get_groups', const {});
            _send('get_users', const {});
            print('🔄 RELAY: состояние после переподключения синхронизировано');
          }
          // login_success was delivered before asynchronous bootstrap.
          return;
        }
      }

      if (type == 'communication_state') {
        final contact = data['contact']?.toString().trim() ?? '';
        if (contact.isNotEmpty) {
          _communicationStates[contact.toLowerCase()] =
              Map<String, dynamic>.from(data);
        }
      }

      if (type == 'communication_request_status') {
        final to = data['to']?.toString().trim() ?? '';
        if (to.isNotEmpty) {
          final previous = _communicationStates[to.toLowerCase()];
          final accepted = data['accepted'] == true;
          final pending = data['pending'] == true;
          _communicationStates[to.toLowerCase()] = <String, dynamic>{
            if (previous != null) ...previous,
            'contact': to,
            'status': accepted
                ? 'accepted'
                : pending
                ? 'pending'
                : (previous?['status'] ?? 'none'),
            'from': currentUser,
            'to': to,
            'incoming': false,
            'outgoing': pending,
            ...data,
          };
        }
      }
      if (type == 'communication_request_response') {
        final me = currentUser?.trim().toLowerCase() ?? '';
        final from = data['from']?.toString().trim() ?? '';
        final to = data['to']?.toString().trim() ?? '';
        final peer = from.toLowerCase() == me ? to : from;
        if (peer.isNotEmpty) {
          _communicationStates[peer.toLowerCase()] = {'contact': peer, ...data};
        }
      }

      if (type == 'communication_request') {
        final from = data['from']?.toString().trim() ?? '';
        if (from.isNotEmpty) {
          _communicationStates[from.toLowerCase()] = {'contact': from, ...data};
        }
      }

      if (type == 'user_profile' || type == 'user_profile_updated') {
        final username = data['username']?.toString().trim() ?? '';
        if (username.isNotEmpty) {
          _userProfiles[username.toLowerCase()] = Map<String, dynamic>.from(
            data,
          );
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

      if (type == 'e2ee_decrypt_failure') {
        // Notification only: never reset trust or resend from this event.
        if (!SocketEventGenerationGuard.isCurrent(
              eventGeneration: generation,
              currentGeneration: _connectionGeneration,
              eventChannel: channel,
              currentChannel: _channel,
            ) ||
            !isAuthenticated) {
          return;
        }

        final owner = currentUser?.trim() ?? '';
        final eventSender = data['from']?.toString().trim() ?? '';
        final peer = data['to']?.toString().trim() ?? '';
        final messageId = data['messageId']?.toString().trim() ?? '';

        if (owner.isEmpty ||
            eventSender != owner ||
            peer.isEmpty ||
            peer == owner ||
            !RegExp(r'^[A-Za-z0-9_-]{6,120}$').hasMatch(messageId)) {
          return;
        }

        final originalMessage = StorageService.getOutboxMessages(owner)
            .where(
              (item) =>
                  item['id']?.toString().trim() == messageId &&
                  item['from']?.toString().trim() == owner &&
                  item['to']?.toString().trim() == peer &&
                  item['e2ee'] == true &&
                  item['status']?.toString() == 'server_accepted',
            )
            .toList();

        if (originalMessage.length != 1) {
          return;
        }

        // Preserve plaintext locally for a controlled future re-encryption.
        // Do not send again or reset Signal trust here.
        StorageService.updateOutboxStatus(owner, messageId, 'decrypt_failed');
        // Confirmed failure: refresh the same trusted Signal identity.
        // Never reset keys, delete history or automatically resend.
        final recoveryKey = '$owner:$peer';
        final recoveryNow = DateTime.now().toUtc();

        // Expire old attempt records and bound memory usage.
        _e2eeRecoveryAttempts.removeWhere(
          (_, attemptedAt) =>
              recoveryNow.difference(attemptedAt) >=
              const Duration(minutes: 10),
        );

        final previousAttempt = _e2eeRecoveryAttempts[recoveryKey];
        final cooldownActive =
            previousAttempt != null &&
            recoveryNow.difference(previousAttempt) <
                const Duration(minutes: 10);

        if (!cooldownActive && _e2eeRecoveryPeers.add(peer)) {
          _e2eeRecoveryAttempts[recoveryKey] = recoveryNow;
          if (_e2eeRecoveryAttempts.length > 128) {
            _e2eeRecoveryAttempts.remove(_e2eeRecoveryAttempts.keys.first);
          }
          final recoveryGeneration = _connectionGeneration;
          final recoveryChannel = _channel;
          unawaited(() async {
            try {
              final refreshed = await requestFreshE2eeSession(peer);
              if (!refreshed ||
                  !SocketEventGenerationGuard.isCurrent(
                    eventGeneration: recoveryGeneration,
                    currentGeneration: _connectionGeneration,
                    eventChannel: recoveryChannel,
                    currentChannel: _channel,
                  ) ||
                  !isAuthenticated ||
                  currentUser?.trim() != owner) {
                return;
              }
              _notifyHandlers({
                'type': 'e2ee_recovery_ready',
                'data': {'to': peer, 'failedMessageId': messageId},
              });
            } catch (_) {
              // The original failed message stays available for recovery.
            } finally {
              _e2eeRecoveryPeers.remove(peer);
            }
          }());
        }

        _notifyHandlers({
          'type': 'e2ee_decrypt_failure',
          'data': {'messageId': messageId, 'from': owner, 'to': peer},
        });
        return;
      }
      if (type == 'e2ee_prekey_bundle') {
        // Reject responses from an obsolete socket or account.
        // This does not replace server-side request correlation.
        if (!SocketEventGenerationGuard.isCurrent(
              eventGeneration: generation,
              currentGeneration: _connectionGeneration,
              eventChannel: channel,
              currentChannel: _channel,
            ) ||
            !isAuthenticated ||
            currentUser?.trim().isNotEmpty != true) {
          return;
        }
        final username = data['username']?.toString().trim() ?? '';
        final expectedRequestId = _e2eeBundleRequestIds[username];
        final responseRequestId = data['requestId']?.toString() ?? '';
        // Reject a mismatched echo. Empty echoes remain supported until
        // the public server is updated and verified.
        if ((_e2eePreviewPeers.contains(username) &&
                responseRequestId != expectedRequestId) ||
            (responseRequestId.isNotEmpty &&
                responseRequestId != expectedRequestId)) {
          return;
        }
        _e2eeBundleRequestIds.remove(username);
        final request = _e2eeBundleRequests.remove(username);
        if (request != null && !request.isCompleted) {
          if (data['available'] == true) {
            if (_e2eePreviewPeers.remove(username)) {
              // Never accept an identity while merely fetching a preview.
              request.complete(data);
            } else {
              try {
                await SignalE2eeService.instance.processRemoteBundle(
                  username,
                  data,
                );
                request.complete(data);
              } catch (error) {
                request.completeError(error);
              }
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
          if (!accepted) {
            // Preserve Signal session and remote identity on legacy invite rejection.
            await E2eeSettingsService.instance.clearFingerprintVerification(
              user,
              peer,
            );
          }
        }
      }

      if (type == 'e2ee_message_error') {
        final id = data['id']?.toString().trim() ?? '';
        final user = currentUser?.trim() ?? '';
        if (id.isNotEmpty && user.isNotEmpty) {
          _e2eeSendingIds.remove(id);
          final retryable =
              data['retryable'] == true ||
              data['code']?.toString() == 'e2ee_keys_pending';
          final status = retryable ? 'queued' : 'failed';
          StorageService.updateOutboxStatus(user, id, status);
          final local = StorageService.getOutboxMessages(user)
              .where((item) => item['id']?.toString() == id)
              .cast<Map<String, dynamic>?>()
              .firstWhere((item) => item != null, orElse: () => null);
          _notifyHandlers({
            'type': retryable ? 'outbox_queued' : 'outbox_failed',
            'data': {
              ...?local,
              'id': id,
              'status': status,
              if (retryable) 'waitingForE2ee': true,
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
        // Never accept a live private message as plaintext.
        // Existing local message history is not modified here.
        if (!const E2eeInboundPolicy().allowsNetworkMessage(
          e2eeMarker: data['e2ee'],
        )) {
          print('E2EE: plaintext private delivery rejected');
          return;
        }
        if (data['e2ee'] == true) {
          final from = data['from']?.toString().trim() ?? '';
          try {
            if (currentUser?.trim().isNotEmpty != true || from.isEmpty) {
              throw StateError('E2EE sender or local identity is missing');
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
            if (decrypted['kind'] == 'private_edit_v1') {
              // Signal decrypt and envelope identity checks succeeded.
              // Do not treat an edit as a new chat message.
              // The chat consumer will validate the target and persist it.
              // Signal decryption may outlive the WebSocket or account.
              // Never deliver a stale edit into another active session.
              if (!SocketEventGenerationGuard.isCurrent(
                    eventGeneration: generation,
                    currentGeneration: _connectionGeneration,
                    eventChannel: channel,
                    currentChannel: _channel,
                  ) ||
                  !isAuthenticated ||
                  currentUser?.trim() != outerTo.trim() ||
                  from == outerTo ||
                  outerTo.trim().isEmpty) {
                return;
              }
              // Persist the verified edit even when ChatScreen is closed.
              // No UI listener is required for the durable mutation.
              final owner = outerTo.trim();
              final peer = from;
              final targetId =
                  decrypted['targetMessageId']?.toString().trim() ?? '';
              final editId = decrypted['id']?.toString().trim() ?? '';
              if (targetId.isEmpty || editId.isEmpty) return;

              bool saved = false;
              try {
                saved = await StorageService.mutateMessagesDurably(
                  owner,
                  peer,
                  (current) {
                    Map<String, dynamic>? original;
                    for (final item in current) {
                      if (item['id']?.toString().trim() == targetId &&
                          item['from']?.toString().trim() == peer &&
                          item['to']?.toString().trim() == owner) {
                        original = Map<String, dynamic>.from(item);
                        break;
                      }
                    }

                    if (original == null ||
                        !PrivateE2eeEditProtocol.canApply(
                          payload: decrypted,
                          original: original,
                          authenticatedFrom: from,
                          localUser: owner,
                          peer: peer,
                        )) {
                      return null;
                    }

                    for (final item in current) {
                      if (item['id']?.toString().trim() == targetId &&
                          item['from']?.toString().trim() == peer &&
                          item['to']?.toString().trim() == owner) {
                        item['text'] = decrypted['newText'];
                        item['isEdited'] = true;
                        item['editedAt'] = decrypted['editedAt'];
                        item['lastEditEventId'] = editId;
                      }

                      final reply = item['replyTo'];
                      if (reply is Map &&
                          reply['id']?.toString().trim() == targetId) {
                        item['replyTo'] = {
                          ...Map<String, dynamic>.from(reply),
                          'text': decrypted['newText'],
                        };
                      }
                    }
                    return current;
                  },
                );
              } catch (_) {
                // Do not disclose edited text or Signal session details.
              }

              // Duplicate delivery is safe if this exact edit was saved.
              if (!saved) {
                saved = StorageService.getMessagesVisibleForOwner(owner, peer)
                    .any(
                      (item) =>
                          item['id']?.toString().trim() == targetId &&
                          item['from']?.toString().trim() == peer &&
                          item['to']?.toString().trim() == owner &&
                          item['e2ee'] == true &&
                          item['lastEditEventId']?.toString().trim() == editId,
                    );
              }

              if (!saved ||
                  !SocketEventGenerationGuard.isCurrent(
                    eventGeneration: generation,
                    currentGeneration: _connectionGeneration,
                    eventChannel: channel,
                    currentChannel: _channel,
                  ) ||
                  !isAuthenticated ||
                  currentUser?.trim() != owner) {
                return;
              }

              // Notify the open chat only after durable persistence.
              _notifyHandlers({
                'type': 'private_e2ee_edit',
                'data': {...decrypted, 'authenticatedFrom': from},
              });
              return;
            }
          } catch (error) {
            final signalFailure = error.toString().toLowerCase();
            final signalCategory = signalFailure.contains('identity')
                ? 'IDENTITY'
                : signalFailure.contains('session')
                ? 'SESSION'
                : signalFailure.contains('duplicate')
                ? 'DUPLICATE'
                : signalFailure.contains('mac') ||
                      signalFailure.contains('authentication')
                ? 'AUTHENTICATION'
                : signalFailure.contains('prekey') ||
                      signalFailure.contains('pre-key')
                ? 'PREKEY'
                : signalFailure.contains('cipher') ||
                      signalFailure.contains('decrypt')
                ? 'CIPHER'
                : 'OTHER';
            final signalDetail =
                signalFailure.contains('untrusted identity') ||
                    signalFailure.contains('identity changed')
                ? 'IDENTITY_CHANGED'
                : signalFailure.contains('invalid mac') ||
                      signalFailure.contains('bad mac') ||
                      signalFailure.contains('mac verification')
                ? 'MAC_FAILURE'
                : signalFailure.contains('duplicate')
                ? 'DUPLICATE_MESSAGE'
                : signalFailure.contains('invalid prekey') ||
                      signalFailure.contains('invalid pre-key')
                ? 'INVALID_PREKEY'
                : signalFailure.contains('no session') ||
                      signalFailure.contains('session not found')
                ? 'MISSING_SESSION'
                : signalFailure.contains('invalid message') ||
                      signalFailure.contains('invalidmessage')
                ? 'INVALID_MESSAGE'
                : signalFailure.contains('invalid key')
                ? 'INVALID_KEY'
                : signalFailure.contains('decrypt')
                ? 'GENERIC_DECRYPT'
                : 'UNCLASSIFIED';
            final messageTime = DateTime.tryParse(
              data['time']?.toString() ?? '',
            );
            final messageAge = messageTime == null
                ? 'UNKNOWN'
                : DateTime.now().toUtc().difference(messageTime.toUtc()) >
                      const Duration(minutes: 5)
                ? 'OLDER_THAN_5_MIN'
                : 'RECENT_OR_FUTURE';
            print(
              'FENYVO_E2EE_RX category=$signalCategory '
              'detail=$signalDetail age=$messageAge '
              'type=${error.runtimeType}',
            );
            data
              ..['text'] = '🔒 Не удалось расшифровать сообщение'
              ..['e2eeError'] = true;
            message['data'] = data;
            // Report only a verified connection and the failed message ID.
            // No plaintext, ciphertext or key material leaves this handler.
            final failureId = data['id']?.toString().trim() ?? '';
            final failureTo = data['to']?.toString().trim() ?? '';
            final failureOwner = currentUser?.trim() ?? '';
            if (SocketEventGenerationGuard.isCurrent(
                  eventGeneration: generation,
                  currentGeneration: _connectionGeneration,
                  eventChannel: channel,
                  currentChannel: _channel,
                ) &&
                isAuthenticated &&
                failureOwner.isNotEmpty &&
                failureOwner == failureTo &&
                from.isNotEmpty &&
                from != failureOwner &&
                data['e2ee'] == true &&
                RegExp(r'^[A-Za-z0-9_-]{6,120}$').hasMatch(failureId)) {
              _send('e2ee_decrypt_failed', {
                'messageId': failureId,
                'from': from,
              });
            }
            // A local diagnostic UI event only; no key material, ciphertext,
            // plaintext, or unverified recovery instruction is emitted.
            if (from.isNotEmpty &&
                from != (currentUser?.trim() ?? '') &&
                SocketEventGenerationGuard.isCurrent(
                  eventGeneration: generation,
                  currentGeneration: _connectionGeneration,
                  eventChannel: channel,
                  currentChannel: _channel,
                ) &&
                isAuthenticated) {
              _notifyHandlers({
                'type': 'e2ee_local_decrypt_failure',
                'data': {'peer': from},
              });
            }
            print('🔒 E2EE: сообщение не расшифровано');
            return;
          }
        }

        final from = data['from']?.toString().trim() ?? '';

        final text = data['text']?.toString().trim() ?? '';

        final messageType =
            data['messageType']?.toString().trim().toLowerCase() ?? 'text';

        final voiceDurationMs = int.tryParse(
          data['voiceDurationMs']?.toString() ?? '',
        );

        final fileName = data['fileName']?.toString().trim();

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
        // Only a validated recipient acknowledgement can retire
        // an accepted, encrypted message from the recovery outbox.
        if (SocketEventGenerationGuard.isCurrent(
              eventGeneration: generation,
              currentGeneration: _connectionGeneration,
              eventChannel: channel,
              currentChannel: _channel,
            ) &&
            isAuthenticated) {
          final owner = currentUser?.trim() ?? '';
          final ackFrom = data['from']?.toString().trim() ?? '';
          final ackTo = data['to']?.toString().trim() ?? '';

          if (owner.isNotEmpty &&
              ackFrom == owner &&
              ackTo.isNotEmpty &&
              ackTo != owner &&
              messageId.isNotEmpty) {
            final matching = StorageService.getOutboxMessages(owner)
                .where(
                  (item) =>
                      item['id']?.toString().trim() == messageId &&
                      item['from']?.toString().trim() == owner &&
                      item['to']?.toString().trim() == ackTo &&
                      item['e2ee'] == true &&
                      (item['status']?.toString() == 'server_accepted' ||
                          item['status']?.toString() == 'decrypt_failed'),
                )
                .toList();

            if (matching.length == 1) {
              StorageService.removeOutboxMessage(owner, messageId);
            }
          }
        }

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
        final callScoped = data['scope']?.toString() == 'group_call';
        if (groupId.isNotEmpty &&
            from.isNotEmpty &&
            from != currentUser &&
            !callScoped &&
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
          final editPolicy = const PrivateE2eeEditDeliveryPolicy();
          final pending = StorageService.getOutboxMessages(user)
              .where((item) => item['id']?.toString() == id)
              .cast<Map<String, dynamic>?>()
              .firstWhere((item) => item != null, orElse: () => null);

          if (pending != null && editPolicy.isEditOperation(pending)) {
            final peer = pending['to']?.toString().trim() ?? '';
            final validAck =
                data['e2ee'] == true &&
                data['from']?.toString().trim() == user &&
                data['to']?.toString().trim() == peer &&
                editPolicy.suppressOrdinaryMessageForAck(
                  queued: pending,
                  acknowledgedId: id,
                );

            if (!validAck ||
                !editPolicy.isValidEditOperation(pending) ||
                peer.isEmpty ||
                peer == user ||
                pending['from']?.toString().trim() != user) {
              _e2eeSendingIds.remove(id);
              StorageService.updateOutboxStatus(user, id, 'failed');
              return;
            }

            // Discard ACK from a replaced connection/account.
            if (!SocketEventGenerationGuard.isCurrent(
                  eventGeneration: generation,
                  currentGeneration: _connectionGeneration,
                  eventChannel: channel,
                  currentChannel: _channel,
                ) ||
                currentUser?.trim() != user) {
              return;
            }

            bool saved = false;
            try {
              saved = await StorageService.mutateMessagesDurably(user, peer, (
                current,
              ) {
                Map<String, dynamic>? originalMessage;
                final targetId =
                    pending['targetMessageId']?.toString().trim() ?? '';

                for (final item in current) {
                  if (item['id']?.toString().trim() == targetId &&
                      item['from']?.toString().trim() == user &&
                      item['to']?.toString().trim() == peer) {
                    originalMessage = Map<String, dynamic>.from(item);
                    break;
                  }
                }

                if (originalMessage == null ||
                    !PrivateE2eeEditProtocol.canApply(
                      payload: pending,
                      original: originalMessage,
                      authenticatedFrom: user,
                      localUser: user,
                      peer: peer,
                    )) {
                  return null;
                }

                for (final item in current) {
                  if (item['id']?.toString().trim() == targetId &&
                      item['from']?.toString().trim() == user &&
                      item['to']?.toString().trim() == peer) {
                    item['text'] = pending['newText'];
                    item['isEdited'] = true;
                    item['editedAt'] = pending['editedAt'];
                    item['lastEditEventId'] = id;
                  }

                  final reply = item['replyTo'];
                  if (reply is Map &&
                      reply['id']?.toString().trim() == targetId) {
                    item['replyTo'] = {
                      ...Map<String, dynamic>.from(reply),
                      'text': pending['newText'],
                    };
                  }
                }
                return current;
              });
            } catch (_) {
              // Do not log edited text or encrypted session data.
            }

            // Persistence may already have completed on an earlier ACK.
            // An already-applied event is a successful idempotent result.
            if (!saved) {
              saved = StorageService.getMessagesVisibleForOwner(user, peer).any(
                (item) =>
                    item['id']?.toString().trim() ==
                        pending['targetMessageId']?.toString().trim() &&
                    item['from']?.toString().trim() == user &&
                    item['to']?.toString().trim() == peer &&
                    item['e2ee'] == true &&
                    item['lastEditEventId']?.toString().trim() == id,
              );
            }

            // An asynchronous write must not finish against another login.
            if (!SocketEventGenerationGuard.isCurrent(
                  eventGeneration: generation,
                  currentGeneration: _connectionGeneration,
                  eventChannel: channel,
                  currentChannel: _channel,
                ) ||
                currentUser?.trim() != user) {
              return;
            }

            _e2eeSendingIds.remove(id);

            if (!saved) {
              // Retain pending operation rather than lose confirmed edit.
              StorageService.updateOutboxStatus(user, id, 'queued');
              return;
            }

            StorageService.removeOutboxMessage(user, id);

            if (!SocketEventGenerationGuard.isCurrent(
                  eventGeneration: generation,
                  currentGeneration: _connectionGeneration,
                  eventChannel: channel,
                  currentChannel: _channel,
                ) ||
                currentUser?.trim() != user) {
              return;
            }

            _notifyHandlers({
              'type': 'private_e2ee_edit_sent',
              'data': {
                'id': id,
                'to': peer,
                'operation': Map<String, dynamic>.from(pending),
              },
            });
            return;
          }

          _e2eeSendingIds.remove(id);
          if (data['e2ee'] == true) {
            final local = StorageService.getOutboxMessages(user)
                .where((item) => item['id']?.toString() == id)
                .cast<Map<String, dynamic>?>()
                .firstWhere((item) => item != null, orElse: () => null);
            if (local != null) {
              final confirmedTime = data['time'];
              data.addAll(Map<String, dynamic>.from(local));
              if (confirmedTime != null) data['time'] = confirmedTime;
              data
                ..remove('requiresE2ee')
                ..remove('status');
              message['data'] = data;
            }
          }
          if (data['e2ee'] == true) {
            // Server acceptance is not proof of successful decryption.
            StorageService.updateOutboxStatus(user, id, 'server_accepted');
          } else {
            StorageService.removeOutboxMessage(user, id);
          }
          _notifyHandlers({'type': 'outbox_sent', 'data': data});
        }
      }

      if (const <String>{
            'call_offer',
            'call_answer',
            'call_ice_candidate',
          }.contains(type) &&
          data['e2eeCall'] is Map) {
        final from = data['from']?.toString().trim() ?? '';
        final to = data['to']?.toString().trim() ?? '';
        final id = data['callId']?.toString().trim() ?? '';
        final active = currentUser != null && await isE2eeReadyWith(from);
        if (!active) {
          print('🔒 E2EE CALL: защищённый сигнал отклонён');
          return;
        }
        try {
          await SignalE2eeService.instance.initializeForUser(currentUser!);
          final clear = await SignalE2eeService.instance.decrypt(
            from,
            Map<String, dynamic>.from(data['e2eeCall'] as Map),
          );
          if (clear['kind']?.toString() != type ||
              clear['callId']?.toString() != id ||
              clear['from']?.toString() != from ||
              clear['to']?.toString() != to) {
            throw const FormatException('E2EE call envelope mismatch');
          }
          data
            ..addAll(clear)
            ..remove('e2eeCall')
            ..['callE2ee'] = true;
          message['data'] = data;
        } catch (error) {
          print('🔒 E2EE CALL: сигнал не расшифрован ($error)');
          // Do not leave the caller ringing forever when the peer has a
          // stale/missing Signal session. The caller receives a clear end
          // event and can recreate the session instead.
          if (from.isNotEmpty && id.isNotEmpty) {
            _send('call_reject', {
              'to': from,
              'callId': id,
              'reason': 'e2ee_signal_error',
            });
          }
          return;
        }
      }

      // ======================================
      // ПЕРЕДАЁМ СОБЫТИЕ ЭКРАНАМ
      // ======================================

      // Async E2EE/media work may have run during a reconnect.
      // Do not deliver a completed event from an obsolete connection.
      if (!SocketEventGenerationGuard.isCurrent(
        eventGeneration: generation,
        currentGeneration: _connectionGeneration,
        eventChannel: channel,
        currentChannel: _channel,
      )) {
        return;
      }

      // Never trust an externally supplied internal edit event.
      // Genuine edits are dispatched directly after Signal decryption.
      // Internal edit acknowledgements originate only from the validated
      // local outbox and an authenticated message_sent response.
      if (type == 'private_e2ee_edit_sent') {
        print('E2EE: unverified private edit ACK rejected');
        return;
      }
      if (type == 'private_e2ee_edit') {
        print('E2EE: unverified private edit event rejected');
        return;
      }
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

  void _handleDisconnect({
    required String reason,
    int? generation,
    WebSocketChannel? channel,
  }) {
    if (generation != null && generation != _connectionGeneration) {
      print('ℹ️ Игнорировано отключение старого WebSocket');
      return;
    }
    if (channel != null && !identical(channel, _channel)) {
      print('ℹ️ Игнорировано событие заменённого WebSocket');
      return;
    }
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

    connectionPhase.value = FenyvoConnectionPhase.disconnected;

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

      connectionPhase.value = FenyvoConnectionPhase.connecting;

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
        final recoveryStatus = item['status']?.toString() ?? '';
        if (recoveryStatus == 'server_accepted' ||
            recoveryStatus == 'decrypt_failed') {
          continue;
        }
        final editPolicy = const PrivateE2eeEditDeliveryPolicy();
        if (editPolicy.needsDedicatedRetry(item)) {
          if (!editPolicy.isValidEditOperation(item)) {
            StorageService.updateOutboxStatus(user, id, 'failed');
            continue;
          }
          StorageService.updateOutboxStatus(user, id, 'sending');
          unawaited(_sendE2eeMessage(Map<String, dynamic>.from(item)));
          continue;
        }
        StorageService.updateOutboxStatus(user, id, 'sending');
        _notifyHandlers({'type': 'outbox_sending', 'data': item});
        if (const E2eeDeliveryPolicy().mustEncryptOutboxMessage(item)) {
          unawaited(_sendE2eeMessage(Map<String, dynamic>.from(item)));
          continue;
        }
      }
    } finally {
      _flushingOutbox = false;
    }
  }

  // ========================================
  // РЕГИСТРАЦИЯ
  // ========================================

  void register(
    String username,
    String password, {
    required bool termsAccepted,
    required bool ageConfirmed,
  }) {
    _send('register', {
      'username': username.trim(),
      'password': password,
      'termsAccepted': termsAccepted,
      'ageConfirmed': ageConfirmed,
      'termsVersion': '2026-10-01',
      'privacyVersion': '2026-10-01',
    });
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

    connectionPhase.value = FenyvoConnectionPhase.authenticating;

    _send('login', {'username': user, 'password': password});
  }

  // ========================================
  // ПОЛЬЗОВАТЕЛИ
  // ========================================

  bool registerRecoveryKey({
    required String publicKeyHex,
    required String password,
  }) {
    if (!_isConnected ||
        !_authenticated ||
        password.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(publicKeyHex)) {
      return false;
    }
    return _send('recovery_key_register', {
      'publicKeyHex': publicKeyHex,
      'password': password,
    });
  }

  bool requestRecoveryChallenge(String username) {
    final user = username.trim();
    if (user.isEmpty || !_isConnected) return false;
    return _send('recovery_challenge_request', {'username': user});
  }

  bool submitRecoveryPassword({
    required String username,
    required String challengeId,
    required String signatureHex,
    required String newPassword,
  }) {
    final user = username.trim();
    if (user.isEmpty ||
        !_isConnected ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(challengeId) ||
        !RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex) ||
        newPassword.length < 8 ||
        newPassword.length > 128) {
      return false;
    }
    return _send('recovery_password_submit', {
      'username': user,
      'challengeId': challengeId,
      'signatureHex': signatureHex,
      'newPassword': newPassword,
    });
  }

  /// Fetch this authenticated account's presence privacy settings.
  void getPresencePrivacy({String? requestId}) {
    if (!isAuthenticated) return;
    _send('get_presence_privacy', <String, dynamic>{
      if (requestId != null) 'requestId': requestId,
    });
  }

  /// Update only the provided presence visibility fields.
  /// The server remains authoritative for validation and persistence.
  void updatePresencePrivacy({
    String? onlineVisibility,
    String? lastSeenVisibility,
    String? requestId,
  }) {
    if (!isAuthenticated) return;

    const valid = <String>{'all', 'contacts', 'nobody'};
    final settings = <String, dynamic>{};

    if (onlineVisibility != null) {
      if (!valid.contains(onlineVisibility)) {
        throw ArgumentError.value(onlineVisibility, 'onlineVisibility');
      }
      settings['onlineVisibility'] = onlineVisibility;
    }

    if (lastSeenVisibility != null) {
      if (!valid.contains(lastSeenVisibility)) {
        throw ArgumentError.value(lastSeenVisibility, 'lastSeenVisibility');
      }
      settings['lastSeenVisibility'] = lastSeenVisibility;
    }

    if (settings.isEmpty) return;
    _send('set_presence_privacy', <String, dynamic>{
      'settings': settings,
      if (requestId != null) 'requestId': requestId,
    });
  }

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

  void getGroupMessages(
    String groupId, {
    String? before,
    int limit = 60,
    String? callId,
  }) {
    final id = groupId.trim();
    if (id.isEmpty) return;

    final data = <String, dynamic>{
      'groupId': id,
      'limit': limit.clamp(20, 100),
    };
    final cursor = before?.trim() ?? '';
    if (cursor.isNotEmpty) data['before'] = cursor;
    final scopedCallId = callId?.trim() ?? '';
    if (scopedCallId.isNotEmpty) data['callId'] = scopedCallId;

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
    String? callId,
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
      if (callId?.trim().isNotEmpty == true) ...{
        'scope': 'group_call',
        'callId': callId!.trim(),
      },
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
    String? callId,
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
      if (callId?.trim().isNotEmpty == true) ...{
        'scope': 'group_call',
        'callId': callId!.trim(),
      },
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

  // ========================================
  // ЗАПРОСЫ СВЯЗИ
  // ========================================

  Map<String, dynamic>? communicationState(String username) {
    final user = username.trim().toLowerCase();
    if (user.isEmpty) return null;
    return _communicationStates[user];
  }

  bool isCommunicationAccepted(String username) {
    return communicationState(username)?['status'] == 'accepted';
  }

  void requestCommunication(String username, {String message = ''}) {
    final user = username.trim();
    if (user.isEmpty) return;
    final note = message.trim();
    _send('communication_request', {
      'to': user,
      if (note.isNotEmpty) 'message': note,
    });
  }

  void respondCommunicationRequest(String username, {required bool accepted}) {
    final user = username.trim();
    if (user.isEmpty) return;
    _send('communication_request_response', {
      'from': user,
      'accepted': accepted,
    });
  }

  void getCommunicationState(String username) {
    final user = username.trim();
    if (user.isEmpty) return;
    _send('get_communication_state', {'contact': user});
  }

  /// Запрашивает список подтверждённых контактов
  /// текущего пользователя с сервера Fenyvo.
  void getContacts() {
    _send('get_contacts', const {});
  }

  void getCommunicationRequests() {
    _send('get_communication_requests', const {});
  }

  Map<String, dynamic>? userProfile(String username) {
    final value = _userProfiles[username.trim().toLowerCase()];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  void getUserProfile(String username) {
    final user = username.trim();
    if (user.isNotEmpty) _send('get_user_profile', {'username': user});
  }

  void updateUserProfile({
    required String about,
    required String region,
    required String statusText,
    required String phone,
    required String birthDate,
    required bool phoneVisible,
    required bool birthDateVisible,
  }) {
    _send('update_user_profile', {
      'about': about.trim(),
      'region': region.trim(),
      'statusText': statusText.trim(),
      'phone': phone.trim(),
      'birthDate': birthDate.trim(),
      'phoneVisible': phoneVisible,
      'birthDateVisible': birthDateVisible,
    });
  }

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

  // Recording statuses are ephemeral; do not attach media data.
  void sendRecordingActivity(
    String to, {
    required String kind,
    required bool active,
  }) {
    final target = to.trim();
    if (target.isEmpty ||
        (kind != 'voice' && kind != 'video') ||
        !isAuthenticated ||
        currentUser == null ||
        currentUser!.trim().isEmpty) {
      return;
    }
    _send('chat_recording_activity', <String, dynamic>{
      'to': target,
      'kind': kind,
      'active': active,
    });
  }

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
    Map<String, dynamic>? sharedContact,
  }) {
    final target = to.trim();

    final messageText = text.trim();

    if (target.isEmpty || messageText.isEmpty) {
      return '';
    }

    final messageData = <String, dynamic>{
      'id': MessageIdGenerator.generate(),
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

    if (sharedContact != null) {
      final username = sharedContact['username']?.toString().trim() ?? '';
      if (username.isNotEmpty) {
        messageData['sharedContact'] = Map<String, dynamic>.from(sharedContact);
      }
    }

    final user = currentUser?.trim() ?? '';
    if (user.isEmpty) return '';
    final connected = _isConnected && _channel != null;
    final protectWithE2ee = const E2eeDeliveryPolicy().requiresEncryption(
      isPrivateMessage: true,
    );
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

    if (connected) {
      unawaited(_sendE2eeMessage(Map<String, dynamic>.from(messageData)));
    }
    return messageData['id'].toString();
  }

  Future<bool> setE2eeEnabled(bool enabled) async {
    // The old UI cannot disable mandatory private E2EE.
    if (!enabled) return false;

    final user = currentUser?.trim() ?? '';
    if (user.isNotEmpty && isAuthenticated) {
      final ready = await _prepareE2ee(user);
      if (!ready) return false;
    }

    await E2eeSettingsService.instance.setEnabled(true);
    _e2eeEnabled = true;
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
    if (!accepted) {
      // Preserve Signal session and remote identity on legacy invite rejection.
      await E2eeSettingsService.instance.clearFingerprintVerification(
        user,
        peer,
      );
    }
    return sent || !accepted;
  }

  Future<bool> _prepareE2ee(String username) async {
    final owner = username.trim();
    final prepareGeneration = _connectionGeneration;
    final prepareChannel = _channel;

    bool prepareStillCurrent() {
      return SocketLoginContinuationGuard.isCurrent(
        eventGeneration: prepareGeneration,
        currentGeneration: _connectionGeneration,
        eventChannel: prepareChannel,
        currentChannel: _channel,
        isAuthenticated: isAuthenticated,
        expectedOwner: owner,
        activeOwner: currentUser,
      );
    }

    if (owner.isEmpty || !prepareStillCurrent()) return false;

    try {
      await SignalE2eeService.instance.initializeForUser(owner);

      // A previous login must not publish keys over a new connection.
      if (!prepareStillCurrent()) return false;

      final bundle = await SignalE2eeService.instance.createPublicBundle();

      // The bundle may have been produced after an account switch.
      if (!prepareStillCurrent()) return false;

      final previous = _e2eePublishRequest;
      if (previous != null && !previous.isCompleted) {
        previous.complete(false);
      }

      final request = Completer<bool>();
      _e2eePublishRequest = request;

      if (!_send('e2ee_publish_bundle', bundle)) {
        if (identical(_e2eePublishRequest, request)) {
          _e2eePublishRequest = null;
        }
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

      // A response to an old publish must not complete new-account setup.
      if (!prepareStillCurrent()) return false;

      if (!accepted) throw StateError('E2EE bundle rejected');

      print('🔐 Signal E2EE готов');
      return true;
    } catch (error) {
      // A cancelled account/connection is not a crypto failure.
      if (!prepareStillCurrent()) return false;

      print('🔒 E2EE не удалось подготовить: $error');
      _notifyHandlers({
        'type': 'e2ee_status',
        'data': {'ready': false, 'reason': 'Не удалось подготовить E2EE'},
      });
      return false;
    }
  }

  /// Requests a fresh Signal session using the existing trusted identity.
  /// This method must be triggered only by an explicit, authenticated
  /// recovery flow. It does not delete a session or an identity.
  Future<bool> requestFreshE2eeSession(String username) async {
    final peer = username.trim();
    final owner = currentUser?.trim() ?? '';

    if (!isAuthenticated || owner.isEmpty || peer.isEmpty || peer == owner) {
      return false;
    }

    final generation = _connectionGeneration;
    final channel = _channel;

    try {
      await _requestE2eeBundle(peer);
    } catch (_) {
      return false;
    }

    return isAuthenticated &&
        currentUser?.trim() == owner &&
        generation == _connectionGeneration &&
        identical(channel, _channel);
  }

  // Correlation tokens are scoped to pending bundle requests.
  final Map<String, String> _e2eeBundleRequestIds = {};
  final Set<String> _e2eePreviewPeers = <String>{};
  int _e2eeBundleSerial = 0;

  /// Authenticated, single-use candidate preview: no session or trust writes.
  Future<Map<String, dynamic>> previewE2eeCandidate(String username) async {
    final owner = currentUser?.trim() ?? '';
    final peer = username.trim();
    if (!isAuthenticated ||
        owner.isEmpty ||
        peer.isEmpty ||
        peer == owner ||
        _e2eeBundleRequests.containsKey(peer)) {
      throw StateError('E2EE preview not available');
    }
    final generation = _connectionGeneration;
    final channel = _channel;
    if (!_e2eePreviewPeers.add(peer)) {
      throw StateError('E2EE preview already active');
    }
    try {
      final data = await _requestE2eeBundle(peer);
      if (!isAuthenticated ||
          currentUser?.trim() != owner ||
          generation != _connectionGeneration ||
          !identical(channel, _channel)) {
        throw StateError('E2EE preview owner changed');
      }
      return data;
    } finally {
      _e2eePreviewPeers.remove(peer);
    }
  }

  Future<Map<String, dynamic>> _requestE2eeBundle(String username) async {
    final existing = _e2eeBundleRequests[username];
    if (existing != null) {
      if (_e2eePreviewPeers.contains(username)) {
        throw StateError('E2EE preview conflicts with another request');
      }
      return await existing.future.timeout(const Duration(seconds: 10));
    }
    final completer = Completer<Map<String, dynamic>>();
    _e2eeBundleRequests[username] = completer;
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${++_e2eeBundleSerial}';
    _e2eeBundleRequestIds[username] = requestId;
    if (!_send('e2ee_get_bundle', {
      'username': username,
      'requestId': requestId,
    })) {
      _e2eeBundleRequests.remove(username);
      _e2eeBundleRequestIds.remove(username);
      throw StateError('Нет соединения с сервером');
    }
    return await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _e2eeBundleRequests.remove(username);
        _e2eeBundleRequestIds.remove(username);
        throw TimeoutException('E2EE key request timed out');
      },
    );
  }

  Future<void> _sendE2eeMessage(Map<String, dynamic> localMessage) async {
    final user = currentUser?.trim() ?? '';
    final id = localMessage['id']?.toString().trim() ?? '';
    final target = localMessage['to']?.toString().trim() ?? '';
    final from = localMessage['from']?.toString().trim() ?? '';

    // Capture the connection that owns this encryption operation.
    final sendGeneration = _connectionGeneration;
    final sendChannel = _channel;

    bool sendStillCurrent() {
      return SocketLoginContinuationGuard.isCurrent(
        eventGeneration: sendGeneration,
        currentGeneration: _connectionGeneration,
        eventChannel: sendChannel,
        currentChannel: _channel,
        isAuthenticated: isAuthenticated,
        expectedOwner: user,
        activeOwner: currentUser,
      );
    }

    if (user.isEmpty ||
        id.isEmpty ||
        target.isEmpty ||
        (from.isNotEmpty && from != user) ||
        !sendStillCurrent()) {
      return;
    }

    if (!_e2eeSendingIds.add(id)) return;

    // Preserve the old owner's outbox for a later retry, without sending
    // its ciphertext through a replacement account or WebSocket.
    void parkStaleSend() {
      _e2eeSendingIds.remove(id);
      StorageService.updateOutboxStatus(user, id, 'queued');
    }

    try {
      await SignalE2eeService.instance.initializeForUser(user);
      if (!sendStillCurrent()) {
        parkStaleSend();
        return;
      }

      final editPolicy = const PrivateE2eeEditDeliveryPolicy();
      final isPrivateEdit = editPolicy.isEditOperation(localMessage);

      if (isPrivateEdit && !editPolicy.isValidEditOperation(localMessage)) {
        throw StateError('Invalid encrypted edit operation');
      }

      final securePayload = isPrivateEdit
          ? <String, dynamic>{
              'kind': localMessage['kind'],
              'id': id,
              'from': user,
              'to': target,
              'targetMessageId': localMessage['targetMessageId'],
              'newText': localMessage['newText'],
              'editedAt': localMessage['editedAt'],
            }
          : _privateE2eePayload(localMessage, user);

      Map<String, dynamic> encrypted;
      try {
        encrypted = await SignalE2eeService.instance.encrypt(
          target,
          securePayload,
        );
      } on E2eeSessionMissing {
        if (!sendStillCurrent()) {
          parkStaleSend();
          return;
        }

        await _requestE2eeBundle(target);

        if (!sendStillCurrent()) {
          parkStaleSend();
          return;
        }

        encrypted = await SignalE2eeService.instance.encrypt(
          target,
          securePayload,
        );
      }
      // Encryption can finish after logout or connection replacement.
      if (!sendStillCurrent()) {
        parkStaleSend();
        return;
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
      final signalFailure = error.toString().toLowerCase();
      final signalCategory = signalFailure.contains('identity')
          ? 'IDENTITY'
          : signalFailure.contains('session')
          ? 'SESSION'
          : signalFailure.contains('timed out') ||
                signalFailure.contains('timeout')
          ? 'TIMEOUT'
          : signalFailure.contains('key') || signalFailure.contains('bundle')
          ? 'KEY_BUNDLE'
          : signalFailure.contains('connect') ||
                signalFailure.contains('сервер')
          ? 'CONNECTION'
          : 'OTHER';
      print(
        'FENYVO_E2EE_TX category=$signalCategory '
        'type=${error.runtimeType}',
      );
      // A cancelled session is a retry condition, not a crypto failure.
      if (!sendStillCurrent()) {
        parkStaleSend();
        return;
      }

      _e2eeSendingIds.remove(id);
      final retryable =
          error is E2eeSessionMissing ||
          signalCategory == 'TIMEOUT' ||
          signalCategory == 'KEY_BUNDLE' ||
          signalCategory == 'CONNECTION';
      final status = retryable ? 'queued' : 'failed';
      StorageService.updateOutboxStatus(user, id, status);
      _notifyHandlers({
        'type': retryable ? 'outbox_queued' : 'outbox_failed',
        'data': {
          ...localMessage,
          'status': status,
          if (retryable) 'waitingForE2ee': true,
          'reason': retryable
              ? 'Ожидаем E2EE-ключ собеседника'
              : 'Не удалось отправить защищённое сообщение',
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
    if (message['messageType'] != null) 'messageType': message['messageType'],
    if (message['sharedContact'] is Map)
      'sharedContact': Map<String, dynamic>.from(
        message['sharedContact'] as Map,
      ),
    if (message['mediaId'] != null) 'mediaId': message['mediaId'],
    if (message['fileName'] != null) 'fileName': message['fileName'],
    if (message['fileSize'] != null) 'fileSize': message['fileSize'],
    if (message['mimeType'] != null) 'mimeType': message['mimeType'],
    if (message['voiceDurationMs'] != null)
      'voiceDurationMs': message['voiceDurationMs'],
    if (message['voiceMimeType'] != null)
      'voiceMimeType': message['voiceMimeType'],
    if (message['e2eeMedia'] is Map)
      'e2eeMedia': Map<String, dynamic>.from(message['e2eeMedia'] as Map),
  };

  // ========================================
  // STAGE 29 - PRIVATE MEDIA
  // ========================================

  /// Requests an explicit owner-approved regrant for an existing media item.
  ///
  /// This is a transport-only API. The UI must obtain informed confirmation,
  /// and the server must independently verify owner and recipient eligibility.
  /// No regrant is submitted without ownerConfirmed == true.
  bool requestLegacyMediaRegrant({
    required String mediaId,
    required String recipient,
    required bool ownerConfirmed,
    required String requestId,
  }) {
    final id = mediaId.trim();
    final target = recipient.trim();
    final actor = currentUser?.trim() ?? '';
    final idRequest = requestId.trim();

    if (!ownerConfirmed ||
        !_authenticated ||
        !_isConnected ||
        _channel == null ||
        actor.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(idRequest) ||
        id.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(id) ||
        target.isEmpty ||
        target == actor) {
      return false;
    }

    _send('legacy_media_regrant', {
      'mediaId': id,
      'recipient': target,
      'confirm': true,
      'requestId': idRequest,
    });

    // Indicates only that the request was submitted to the transport.
    // Server approval must be determined from legacy_media_regrant_result.
    return true;
  }

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
    Map<String, dynamic>? e2eeMedia,
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
    final user = currentUser?.trim() ?? '';
    final protectWithE2ee = const E2eeDeliveryPolicy().requiresEncryption(
      isPrivateMessage: true,
    );
    if (protectWithE2ee && (e2eeMedia == null || user.isEmpty)) {
      print('🔒 E2EE: незашифрованное вложение заблокировано');
      return;
    }
    if (protectWithE2ee) {
      data
        ..['from'] = user
        ..['e2eeMedia'] = Map<String, dynamic>.from(e2eeMedia!)
        ..['requiresE2ee'] = true
        ..['e2ee'] = true
        ..['status'] = 'sending'
        ..['isMe'] = true;
      StorageService.saveOutboxMessage(user, data);
      _notifyHandlers({'type': 'outbox_sending', 'data': data});
      unawaited(_sendE2eeMessage(Map<String, dynamic>.from(data)));
      return;
    }
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
    Map<String, dynamic>? e2eeMedia,
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

    final user = currentUser?.trim() ?? '';
    final protectWithE2ee = const E2eeDeliveryPolicy().requiresEncryption(
      isPrivateMessage: true,
    );
    if (protectWithE2ee && (e2eeMedia == null || user.isEmpty)) {
      print('🔒 E2EE: незашифрованное голосовое заблокировано');
      return;
    }
    if (protectWithE2ee) {
      messageData
        ..['from'] = user
        ..['e2eeMedia'] = Map<String, dynamic>.from(e2eeMedia!)
        ..['requiresE2ee'] = true
        ..['e2ee'] = true
        ..['status'] = 'sending'
        ..['isMe'] = true;
      StorageService.saveOutboxMessage(user, messageData);
      _notifyHandlers({'type': 'outbox_sending', 'data': messageData});
      unawaited(_sendE2eeMessage(Map<String, dynamic>.from(messageData)));
      return;
    }
  }

  // ========================================
  // РЕДАКТИРОВАНИЕ СООБЩЕНИЯ
  // ========================================

  /// Creates a Signal-only edit operation for a message owned by this user.
  ///
  /// Returns false when validation fails. The operation must not be
  /// rendered as a new chat message.
  bool sendPrivateE2eeEdit({
    required Map<String, dynamic> originalMessage,
    required String to,
    required String newText,
  }) {
    final owner = currentUser?.trim() ?? '';
    final peer = to.trim();
    final originalId = originalMessage['id']?.toString().trim() ?? '';
    final originalFrom = originalMessage['from']?.toString().trim() ?? '';
    final originalTo = originalMessage['to']?.toString().trim() ?? '';
    final cleanText = newText.trim();
    final existingText = originalMessage['text']?.toString().trim() ?? '';
    final forwardedFrom =
        originalMessage['forwardedFrom']?.toString().trim() ?? '';
    final messageType =
        originalMessage['messageType']?.toString().trim().toLowerCase() ??
        'text';

    // Never allow edits based on a different account or untrusted target.
    if (!_isConnected ||
        !isAuthenticated ||
        owner.isEmpty ||
        peer.isEmpty ||
        owner == peer ||
        originalId.isEmpty ||
        originalFrom != owner ||
        originalTo != peer ||
        originalMessage['e2ee'] != true ||
        forwardedFrom.isNotEmpty ||
        messageType != 'text' ||
        cleanText.isEmpty ||
        cleanText == existingText ||
        cleanText.length > PrivateE2eeEditProtocol.maxTextLength) {
      return false;
    }

    Map<String, dynamic> edit;
    try {
      final random = Random.secure();
      final eventId =
          'edit_${DateTime.now().microsecondsSinceEpoch}_'
          '${random.nextInt(1 << 32)}';

      edit = PrivateE2eeEditProtocol.create(
        eventId: eventId,
        from: owner,
        to: peer,
        targetMessageId: originalId,
        newText: cleanText,
        editedAt: DateTime.now().toUtc(),
      );

      if (!PrivateE2eeEditProtocol.canApply(
        payload: edit,
        original: originalMessage,
        authenticatedFrom: owner,
        localUser: owner,
        peer: peer,
      )) {
        return false;
      }
    } catch (_) {
      return false;
    }

    // Only local outbox receives the clear operation. The network
    // sender encrypts the dedicated payload with Signal.
    final queuedEdit = <String, dynamic>{
      ...edit,
      'e2ee': true,
      'requiresE2ee': true,
      'status': 'queued',
    };

    StorageService.saveOutboxMessage(owner, queuedEdit);
    unawaited(_sendE2eeMessage(Map<String, dynamic>.from(queuedEdit)));
    return true;
  }

  void editMessage({
    required String messageId,
    required String to,
    required String newText,
  }) {
    // Fail closed: the legacy edit protocol exposes newText.
    // Restore editing only through a verified Signal E2EE protocol.
    print('E2EE: plaintext private edit blocked');
    return;
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

  void sendSupportAiRequest({required String requestId, required String text}) {
    final id = requestId.trim();
    final cleanText = text.trim();

    if (id.isEmpty || cleanText.isEmpty) {
      return;
    }

    _send('support_ai_request', {'requestId': id, 'text': cleanText});
  }

  bool sendSupportTicketRequest({
    required String requestId,
    required String text,
    required String email,
    required bool consent,
  }) {
    final id = requestId.trim();
    final body = text.trim();
    final contact = email.trim();
    if (!isAuthenticated ||
        consent != true ||
        !RegExp(r'^[a-zA-Z0-9_-]{8,100}$').hasMatch(id) ||
        body.length < 5 ||
        body.length > 2000 ||
        contact.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)) {
      return false;
    }
    return _send('support_ticket_request', {
      'requestId': id,
      'text': body,
      'email': contact,
      'consent': true,
    });
  }

  // ========================================
  // FENYVO AI
  // ========================================

  void requestFenyvoAiHistory({required String requestId}) {
    final id = requestId.trim();

    if (id.isEmpty) {
      return;
    }

    _send('get_spartan_ai_history', {'requestId': id});
  }

  void sendFenyvoAiRequest({
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

  void clearFenyvoAiHistory({required String requestId}) {
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

  Future<bool> _sendProtectedCallSignal(
    String type, {
    required String to,
    required String callId,
    required Map<String, dynamic> clear,
  }) async {
    final peer = to.trim();
    final id = callId.trim();
    if (peer.isEmpty || id.isEmpty) return false;
    return _send(type, {'to': peer, 'callId': id, ...clear});
  }

  Future<bool> sendCallOffer({
    required String to,
    required String callId,
    required bool video,
    required Map<String, dynamic> sdp,
  }) => _sendProtectedCallSignal(
    'call_offer',
    to: to,
    callId: callId,
    clear: {'video': video, 'sdp': sdp},
  );

  Future<bool> sendCallAnswer({
    required String to,
    required String callId,
    required Map<String, dynamic> sdp,
  }) => _sendProtectedCallSignal(
    'call_answer',
    to: to,
    callId: callId,
    clear: {'sdp': sdp},
  );

  Future<bool> sendCallIceCandidate({
    required String to,
    required String callId,
    required Map<String, dynamic> candidate,
  }) => _sendProtectedCallSignal(
    'call_ice_candidate',
    to: to,
    callId: callId,
    clear: {'candidate': candidate},
  );

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

    // Invalidate callbacks from this socket before any asynchronous
    // account cleanup or channel shutdown can suspend this method.
    ++_connectionGeneration;
    _authenticated = false;
    _isConnected = false;

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

    connectionPhase.value = FenyvoConnectionPhase.disconnected;

    final channel = _channel;

    if (clearUser) {
      _authenticated = false;
      recoveryConfigured = null;
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
