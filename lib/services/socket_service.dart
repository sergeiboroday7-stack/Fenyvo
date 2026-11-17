import 'dart:math';
import 'account_identity_state.dart';
import 'device_transfer_ack.dart';
import 'device_transfer_hint_dispatcher.dart';
import 'new_device_transfer_v2_client.dart';
import 'crypto/device_transfer_request.dart';
import 'crypto/contact_continuity_router.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_messaging_service.dart';
import 'media_transfer_service.dart';
import 'turn_credential_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'app_visibility.dart';
import 'system_call_service.dart';
import 'e2ee_settings_service.dart';
import 'crypto/signal_e2ee_service.dart';
import 'crypto/temporary_signal_e2ee_service.dart' as temp_e2ee;

enum SpartanConnectionPhase {
  disconnected,
  connecting,
  authenticating,
  connected,
}

class SocketService {
  static final SocketService _instance = SocketService._internal();
  static const _ratchetSessionMigration = 'reuse_4228';

  static SocketService get instance => _instance;

  SocketService._internal() {
    AppVisibility.instance.changes.addListener(_syncPresence);
  }

  void _syncPresence() {
    if (!_authenticated || !_isConnected || _channel == null) {
      return;
    }

    _send('presence_update', <String, dynamic>{
      'foreground': AppVisibility.instance.foreground,
    });
  }

  WebSocketChannel? _channel;
  int _connectionGeneration = 0;
  int get deviceTransferSessionGeneration => _connectionGeneration;
  Future<bool>? _connectFuture;
  String? _loginInFlightUser;

  final List<void Function(Map<String, dynamic>)> _messageHandlers = [];

  final Map<String, Map<String, dynamic>> _communicationStates =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _userProfiles =
      <String, Map<String, dynamic>>{};

  String? currentUser;
  final AccountIdentityState _accountIdentity = AccountIdentityState();
  String? get currentAccountId =>
      isAuthenticated ? _accountIdentity.accountIdFor(currentUser) : null;

  final ValueNotifier<DeviceTransferRequest?> pendingDeviceTransfer =
      ValueNotifier<DeviceTransferRequest?>(null);
  int _deviceTransferGeneration = -1;
  final DeviceTransferAck _transferAck = DeviceTransferAck();
  Object? _transferAckScope;
  final Map<
    String,
    ({String id, int epoch, Completer<Map<String, dynamic>> result})
  >
  _continuityRequests = {};
  late final DeviceTransferHintDispatcher _continuityHintDispatcher =
      DeviceTransferHintDispatcher(
        readTrustedHead: (peer, current) => SignalE2eeService.instance
            .contactContinuityHead(peer, isSessionCurrent: current),
        refreshBundle: (peer) async {
          await _requestE2eeBundle(peer);
        },
      );

  bool _transferIsCurrent(DeviceTransferRequest request) =>
      identical(pendingDeviceTransfer.value, request) &&
      isAuthenticated &&
      _deviceTransferGeneration == _connectionGeneration &&
      currentUser == request.username &&
      currentAccountId == request.accountId &&
      request.validAt(DateTime.now().millisecondsSinceEpoch);

  Future<bool> approveDeviceTransfer(
    DeviceTransferRequest request, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed || !_transferIsCurrent(request) || _transferAck.waiting)
      return false;
    final generation = _connectionGeneration, channel = _channel;
    bool current() =>
        _transferIsCurrent(request) &&
        generation == _connectionGeneration &&
        identical(channel, _channel);
    try {
      final proof = await SignalE2eeService.instance
          .signConfirmedDeviceTransfer(
            request,
            userConfirmed: userConfirmed,
            isSessionCurrent: current,
          );
      if (!current()) return false;
      Future<bool>? acknowledgement;
      if (request.fromEpoch != null) {
        if (_transferAck.waiting) return false;
        final scope = Object();
        _transferAckScope = scope;
        final remaining =
            request.expiresAt - DateTime.now().millisecondsSinceEpoch;
        acknowledgement = _transferAck.begin(
          scope: scope,
          nonce: request.nonce,
          timeout: Duration(milliseconds: min(10000, remaining)),
        );
      }
      final sent = _send(
        request.fromEpoch == null
            ? 'device_transfer_proof'
            : 'device_transfer_proof_v2',
        proof,
      );
      if (!sent) _transferAck.cancel();
      final accepted =
          sent && (acknowledgement == null || await acknowledgement);
      final valid = accepted && current();
      if (valid) pendingDeviceTransfer.value = null;
      return valid;
    } catch (_) {
      _transferAck.cancel();
      return false;
    }
  }

  void rejectDeviceTransfer(DeviceTransferRequest request) {
    if (!identical(pendingDeviceTransfer.value, request)) return;
    _transferAck.cancel();
    _transferAckScope = null;
    if (isAuthenticated &&
        _deviceTransferGeneration == _connectionGeneration &&
        currentUser == request.username &&
        currentAccountId == request.accountId) {
      if (request.fromEpoch == null) {
        _send('device_transfer_cancel', {'nonce': request.nonce});
      } else {
        _send('device_transfer_cancel_v2', {'transferNonce': request.nonce});
      }
    }
    pendingDeviceTransfer.value = null;
  }



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

  final Map<String, Completer<Map<String, dynamic>>> _e2eeBundleRequests = {};
  final Set<String> _e2eeSendingIds = <String>{};
  Completer<bool>? _e2eePublishRequest;

  final Map<String, temp_e2ee.TemporarySignalE2eeService>
  _temporaryE2eeServices = <String, temp_e2ee.TemporarySignalE2eeService>{};

  final Map<String, Completer<Map<String, dynamic>>>
  _temporaryE2eeBundleRequests = <String, Completer<Map<String, dynamic>>>{};

  final Map<String, Completer<bool>> _temporaryE2eePublishRequests =
      <String, Completer<bool>>{};

  bool get e2eeEnabled => true;

  bool isE2eeActiveWith(String username) => username.trim().isNotEmpty;

  Future<bool> isE2eeReadyWith(String username) async {
    final user = currentUser?.trim() ?? '';
    final peer = username.trim();
    if (user.isEmpty || peer.isEmpty || !isAuthenticated) return false;
    try {
      await SignalE2eeService.instance.initializeForUser(user);
      if (!await SignalE2eeService.instance.hasSession(peer)) {
        await _requestE2eeBundle(peer);
      }
      return await SignalE2eeService.instance.hasSession(peer);
    } catch (_) {
      return false;
    }
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

  /// Adopts an already verified transfer socket without a second login/listener.
  Future<void> adoptTransferredConnection(
    TransferredDeviceConnection connection, {
    required String password,
  }) async {
    if (_isConnected ||
        _authenticated ||
        _channel != null ||
        currentUser != null && currentUser != connection.username) {
      await connection.abort();
      throw StateError('Ordinary connection must be stopped before handoff');
    }
    final channel = connection.channel;
    final generation = ++_connectionGeneration;
    _channel = channel;
    _serverUrl = connection.server.toString();
    currentUser = connection.username;
    _lastPassword = password;
    _manualDisconnect = false;
    _isConnected = true;
    _authenticated = false;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    connectionPhase.value = SpartanConnectionPhase.authenticating;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (generation == _connectionGeneration &&
          identical(channel, _channel) &&
          _isConnected)
        _send('ping', const {});
    });
    unawaited(() async {
      try {
        await connection.drain((raw) async {
          if (generation != _connectionGeneration ||
              !identical(channel, _channel))
            throw StateError('Transfer handoff superseded');
          unawaited(_handleRawMessage(
            raw,
            generation: generation,
            channel: channel,
          ));
        });
      } catch (_) {
        /* Same generation disconnect below handles recovery. */
      } finally {
        _handleDisconnect(
          reason: 'Transfer connection closed',
          generation: generation,
          channel: channel,
        );
      }
    }());
  }

  Future<bool> connect(String url) {
    final inFlight = _connectFuture;
    if (inFlight != null) {
      print('ℹ️ Подключение уже выполняется, ждём его завершения');
      return inFlight;
    }

    final future = _connectInternal(url);
    _connectFuture = future;
    return future.whenComplete(() {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    });
  }

  Future<bool> _connectInternal(String url) async {
    await E2eeSettingsService.instance.setEnabled(true);
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

      final generation = ++_connectionGeneration;
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      channel.stream.listen(
        (raw) => _handleRawMessage(raw, generation: generation, channel: channel),
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

      _isConnected = true;

      // Keep mobile WebSocket connections alive during quiet call periods.
      // Some Android vendors/NATs silently expire an otherwise idle socket.
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_isConnected && _channel != null) {
          _send('ping', const {});

          // Refresh public presence only while the app is foreground.
          // The ping itself must never make a user appear online.
          if (_authenticated && AppVisibility.instance.foreground) {
            _syncPresence();
          }
        }
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

  Future<void> _handleRawMessage(dynamic rawMessage, {
    required int generation,
    required WebSocketChannel channel,
  }) async {
    if (generation != _connectionGeneration || !identical(channel, _channel)) return;
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

      if (type == 'device_transfer_approved_v2') {
        final pending = pendingDeviceTransfer.value, scope = _transferAckScope;
        if (pending != null && scope != null && _transferIsCurrent(pending))
          _transferAck.receive(data, scope: scope);
        return;
      }
      if (type == 'device_transfer_check_v2') {
        final owner = currentUser;
        final eventGeneration = generation;
        final eventChannel = channel;
        unawaited(
          _continuityHintDispatcher.handle(
            username: data['username'],
            owner: owner,
            enabled:
                const bool.fromEnvironment(
                  'FENYVO_CONTACT_CONTINUITY_ENABLED',
                ) &&
                isAuthenticated,
            isCurrent: () =>
                isAuthenticated &&
                currentUser == owner &&
                eventGeneration == _connectionGeneration &&
                identical(eventChannel, _channel),
          ),
        );
        return;
      }
      if (type == 'device_transfer_certificates_v2') {
        final peer = data['username'], pending = _continuityRequests[peer];
        if (pending != null &&
            isAuthenticated &&
            data['requestId'] == pending.id &&
            data['fromEpoch'] == pending.epoch) {
          _continuityRequests.remove(peer);
          final copy = Map<String, dynamic>.from(data)..remove('requestId');
          if (!pending.result.isCompleted) pending.result.complete(copy);
        }
        return;
      }
      if (type == 'device_transfer_requested_v2') {
        if (type == 'device_transfer_requested_v2' &&
            !(const bool.fromEnvironment('FENYVO_DEVICE_TRANSFER_UI_ENABLED')))
          return;
        final accountId = currentAccountId, username = currentUser;
        if (!isAuthenticated || accountId == null || username == null) return;
        final parser = type == 'device_transfer_requested_v2'
            ? DeviceTransferRequest.parseV2
            : DeviceTransferRequest.parse;
        final request = parser(
          data,
          accountId: accountId,
          username: username,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (request != null) {
          _transferAck.cancel();
          _transferAckScope = null;
          _deviceTransferGeneration = _connectionGeneration;
          pendingDeviceTransfer.value = request;
        }
        return;
      }

      // ======================================
      // УСПЕШНЫЙ ВХОД
      // ======================================

      if (type == 'login_success') {
        _loginInFlightUser = null;
        _authenticated = true;
        connectionPhase.value = SpartanConnectionPhase.connected;
        final username = data['username']?.toString();

        if (username != null && username.isNotEmpty) {
          currentUser = username;
          _accountIdentity.bind(username: username, accountId: data['accountId']);
          _syncPresence();

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

          bool currentLogin() => isAuthenticated && currentUser == username &&
              generation == _connectionGeneration && identical(channel, _channel);
          _sendFcmToken();
          await SystemCallService.configure(serverUrl, username, mediaPort);
          if (!currentLogin()) return;
          final ready = await _prepareE2ee(username);
          if (!ready || !currentLogin()) return;

          _receivingOfflineMessages = true;
          _send('get_offline_messages', const {});

          if (_needsResyncAfterLogin) {
            _needsResyncAfterLogin = false;
            _send('get_communication_requests', const {});
            _send('get_groups', const {});
            _send('get_users', const {});
            print('🔄 RELAY: состояние после переподключения синхронизировано');
          }

          await _flushOutbox();
          if (!currentLogin()) return;
        }
      }

      if (type == 'login_error') {
        _loginInFlightUser = null;
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
        await _migrateLegacyRatchetSessionsOnce();
        await _flushOutbox();

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
              final owner = currentUser;
              bool current() => isAuthenticated && currentUser == owner &&
                  generation == _connectionGeneration && identical(channel, _channel);
              final service = SignalE2eeService.instance;
              var updated = false;
              if (const bool.fromEnvironment('FENYVO_CONTACT_CONTINUITY_ENABLED')) {
                updated = await ContactContinuityRouter(
                  readHead: (peer) => service.contactContinuityHead(peer, isSessionCurrent: current),
                  fetchDirectory: _requestContinuityDirectory,
                  applyVerified: (peer, bundle, accountId, certificates, stillCurrent) => service.acceptContinuityVerifiedRemoteBundle(
                    peer, bundle, expectedAccountId: accountId, certificates: certificates, isSessionCurrent: stillCurrent),
                ).applyIfChanged(username, data, isCurrent: current);
              }
              if (!current()) throw StateError('E2EE response connection changed');
              if (!updated) await service.processRemoteBundleIfMissing(username, data);
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

      if (type == 'temporary_contact_joined') {
        final sessionId = data['sessionId']?.toString().trim() ?? '';
        final role = data['role']?.toString().trim().toLowerCase() ?? '';

        if (sessionId.isNotEmpty && (role == 'owner' || role == 'guest')) {
          unawaited(_prepareTemporaryE2ee(sessionId, role));
        }

        _notifyHandlers({
          'type': 'temporary_contact_joined',
          'data': Map<String, dynamic>.from(data),
        });

        return;
      }

      if (type == 'temporary_e2ee_bundle_published') {
        final sessionId = data['sessionId']?.toString().trim() ?? '';
        final request = _temporaryE2eePublishRequests.remove(sessionId);

        if (request != null && !request.isCompleted) {
          request.complete(data['ok'] == true);
        }

        return;
      }

      if (type == 'temporary_e2ee_prekey_bundle') {
        final sessionId = data['sessionId']?.toString().trim() ?? '';
        final request = _temporaryE2eeBundleRequests.remove(sessionId);

        if (request != null && !request.isCompleted) {
          if (data['available'] == true) {
            request.complete(Map<String, dynamic>.from(data));
          } else {
            request.completeError(
              StateError(
                data['reason']?.toString() ??
                    'Temporary contact keys are unavailable',
              ),
            );
          }
        }

        return;
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

      if (type == 'temporary_message') {
        final sessionId = data['sessionId']?.toString().trim() ?? '';
        final role = data['role']?.toString().trim().toLowerCase() ?? '';
        final messageId = data['messageId']?.toString().trim() ?? '';
        final outerTime = data['time']?.toString() ?? '';

        try {
          final localId = temp_e2ee
              .TemporarySignalE2eeService.identityForSession(sessionId, role);

          final peerId =
              temp_e2ee.TemporarySignalE2eeService.peerIdentityForSession(
                sessionId,
                role,
              );

          final service = _temporaryE2eeServices.putIfAbsent(
            sessionId,
            () => temp_e2ee.TemporarySignalE2eeService(),
          );

          await service.initializeForIdentity(localId);

          final decrypted = await service.decrypt(peerId, data);

          if (decrypted['sessionId']?.toString() != sessionId ||
              decrypted['messageId']?.toString() != messageId ||
              decrypted['time']?.toString() != outerTime) {
            throw const FormatException('Temporary E2EE envelope mismatch');
          }

          final clearText = decrypted['text']?.toString() ?? '';

          if (clearText.isEmpty) {
            throw const FormatException('Temporary E2EE message is empty');
          }

          _notifyHandlers({
            'type': 'temporary_message',
            'data': <String, dynamic>{
              'sessionId': sessionId,
              'messageId': messageId,
              'time': outerTime,
              'role': role,
              'text': clearText,
              'e2ee': true,
              'e2eeVersion': 2,
              'e2eeProtocol': 'signal',
            },
          });

          if (data['cipherType'] == 3) {
            unawaited(_prepareTemporaryE2ee(sessionId, role));
          }
        } catch (error) {
          print('Temporary E2EE: сообщение не расшифровано ($error)');

          _notifyHandlers({
            'type': 'temporary_message_error',
            'data': <String, dynamic>{
              'sessionId': sessionId,
              'messageId': messageId,
              'reason': 'Не удалось расшифровать временное сообщение',
            },
          });
        }

        return;
      }

      if (type == 'e2ee_message_edited') {
        final from = data['from']?.toString().trim() ?? '';
        final outerMessageId = data['messageId']?.toString().trim() ?? '';
        final outerTo = data['to']?.toString().trim() ?? '';
        try {
          final user = currentUser?.trim() ?? '';
          if (user.isEmpty || from.isEmpty) {
            throw StateError('E2EE user is not initialized');
          }
          await SignalE2eeService.instance.initializeForUser(user);
          final decrypted = await SignalE2eeService.instance.decrypt(
            from,
            data,
          );
          if (decrypted['kind']?.toString() != 'edit_message' ||
              decrypted['messageId']?.toString() != outerMessageId ||
              decrypted['from']?.toString() != from ||
              decrypted['to']?.toString() != outerTo) {
            throw const FormatException('E2EE edit envelope mismatch');
          }
          final newText = decrypted['newText']?.toString().trim() ?? '';
          if (newText.isEmpty) {
            throw const FormatException('E2EE edited text is empty');
          }
          _notifyHandlers({
            'type': 'message_edited',
            'data': <String, dynamic>{
              ...decrypted,
              'e2ee': true,
              'e2eeVersion': 2,
            },
          });
          if (data['cipherType'] == 3) {
            unawaited(_prepareE2ee(user));
          }
        } catch (error) {
          print('🔒 E2EE: редактирование не расшифровано');
        }
        return;
      }

      if (type == 'message') {
        if (data['e2ee'] == true) {
          final from = data['from']?.toString().trim() ?? '';
          try {
            if (currentUser == null) {
              throw StateError('E2EE user is not initialized');
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
          _e2eeSendingIds.remove(id);
          if (data['e2ee'] == true) {
            final local = StorageService.getOutboxMessages(user)
                .where((item) => item['id']?.toString() == id)
                .cast<Map<String, dynamic>?>()
                .firstWhere((item) => item != null, orElse: () => null);
            if (local != null) {
              data.addAll(Map<String, dynamic>.from(local));
              data
                ..remove('requiresE2ee')
                ..remove('status');
              message['data'] = data;
            }
          }
          StorageService.removeOutboxMessage(user, id);
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
          if (error.toString().contains('message with old counter')) {
            print('E2EE CALL: duplicate/replayed Signal message ignored');
            return;
          }
          // Do not leave the caller ringing forever when the peer has a
          // stale/missing Signal session. The caller receives a clear end
          // event and can recreate the session instead.
          if (type != 'call_ice_candidate' &&
              from.isNotEmpty &&
              id.isNotEmpty) {
            _send('call_reject', {
              'to': from,
              'callId': id,
              'reason': 'e2ee_signal_error',
            });
            // A failed incoming offer is recovered by the remote caller after
            // it receives the rejection. A failed answer happened on this
            // device's outgoing call, so its CallService must also be told to
            // stop ringback and refresh the peer session locally.
            if (type == 'call_answer') {
              _notifyHandlers({
                'type': 'call_e2ee_answer_error',
                'data': {
                  'callId': id,
                  'from': from,
                  'reason': 'e2ee_signal_error',
                },
              });
            }
          }
          return;
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

  void _clearTransferConnectionState() {
    _transferAck.cancel();
    _transferAckScope = null;
    pendingDeviceTransfer.value = null;
    _accountIdentity.clear();
    for (final request in _continuityRequests.values) {
      if (!request.result.isCompleted) request.result.completeError(StateError('Transfer connection closed'));
    }
    _continuityRequests.clear();
  }

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
    _clearTransferConnectionState();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isConnected = false;
    _authenticated = false;
    _loginInFlightUser = null;
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

    for (final request in _temporaryE2eePublishRequests.values) {
      if (!request.isCompleted) {
        request.complete(false);
      }
    }
    _temporaryE2eePublishRequests.clear();

    for (final request in _temporaryE2eeBundleRequests.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('Connection to server lost'));
      }
    }
    _temporaryE2eeBundleRequests.clear();

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
    if (_flushingOutbox ||
        _receivingOfflineMessages ||
        user.isEmpty ||
        !_isConnected ||
        _channel == null) {
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
        item['requiresE2ee'] = true;
        item['e2ee'] = true;
        unawaited(_sendE2eeMessage(Map<String, dynamic>.from(item)));
        continue;
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
    required String termsVersion,
    required String privacyVersion,
  }) {
    _send('register', {
      'username': username.trim(),
      'password': password,
      'termsAccepted': termsAccepted,
      'ageConfirmed': ageConfirmed,
      'termsVersion': termsVersion,
      'privacyVersion': privacyVersion,
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

    if (_authenticated && currentUser?.toLowerCase() == user.toLowerCase()) {
      print('ℹ️ Повторный login уже авторизованного пользователя пропущен');
      return;
    }

    if (connectionPhase.value == SpartanConnectionPhase.authenticating &&
        _loginInFlightUser?.toLowerCase() == user.toLowerCase()) {
      print('ℹ️ Повторный login во время авторизации пропущен');
      return;
    }

    _manualDisconnect = false;

    currentUser = user;

    _lastPassword = password;
    _loginInFlightUser = user;

    connectionPhase.value = SpartanConnectionPhase.authenticating;

    _send('login', {'username': user, 'password': password});
  }

  void acceptLegal({
    required bool termsAccepted,
    required bool ageConfirmed,
    required String termsVersion,
    required String privacyVersion,
  }) {
    _send('accept_legal', {
      'termsAccepted': termsAccepted,
      'ageConfirmed': ageConfirmed,
      'termsVersion': termsVersion,
      'privacyVersion': privacyVersion,
    });
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
      'disabled': !accepted,
    });
  }

  void getCommunicationState(String username) {
    final user = username.trim();
    if (user.isEmpty) return;
    _send('get_communication_state', {'contact': user});
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
  }) {
    _send('update_user_profile', {
      'about': about.trim(),
      'region': region.trim(),
      'statusText': statusText.trim(),
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
    int autoDeleteAfterReadSeconds = 0,
    int autoDeleteUnreadSeconds = 0,
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
      'autoDeleteAfterReadSeconds': autoDeleteAfterReadSeconds,
      'autoDeleteUnreadSeconds': autoDeleteUnreadSeconds,
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
    final connected =
        _isConnected && _channel != null && !_receivingOfflineMessages;
    if (user.isEmpty || target.isEmpty) {
      return messageData['id'].toString();
    }
    messageData['requiresE2ee'] = true;
    messageData['e2ee'] = true;
    messageData['status'] = connected ? 'sending' : 'queued';
    messageData['isMe'] = true;
    StorageService.saveOutboxMessage(user, messageData);
    _notifyHandlers({
      'type': connected ? 'outbox_sending' : 'outbox_queued',
      'data': messageData,
    });
    if (connected) {
      unawaited(_sendE2eeMessage(Map<String, dynamic>.from(messageData)));
    }
    return messageData['id'].toString();
  }

  Future<Map<String, dynamic>?> createTemporaryContact({
    int durationMinutes = 60,
    bool allowMessages = true,
    bool allowCalls = true,
    bool allowFiles = true,
  }) async {
    if (!isAuthenticated) {
      return null;
    }

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();

    final completer = Completer<Map<String, dynamic>>();

    void handler(Map<String, dynamic> message) {
      if (message['type'] != 'temporary_contact_created') {
        return;
      }

      final data = message['data'];
      if (data is! Map) {
        return;
      }

      final map = Map<String, dynamic>.from(data);

      if (map['requestId']?.toString() != requestId) {
        return;
      }

      if (!completer.isCompleted) {
        completer.complete(map);
      }
    }

    addMessageHandler(handler);

    try {
      final sent = _send('temporary_contact_create', <String, dynamic>{
        'requestId': requestId,
        'durationMinutes': durationMinutes,
        'allowMessages': allowMessages,
        'allowCalls': allowCalls,
        'allowFiles': allowFiles,
      });

      if (!sent) {
        return null;
      }

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => <String, dynamic>{},
      );
    } finally {
      removeMessageHandler(handler);
    }
  }

  bool joinTemporaryContact(String token) {
    final value = token.trim().toLowerCase();

    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value) || !isAuthenticated) {
      return false;
    }

    return _send('temporary_contact_join', <String, dynamic>{'token': value});
  }

  Future<bool> sendTemporaryEncryptedMessage({
    required String sessionId,
    required String role,
    required String text,
    String? messageId,
  }) async {
    final id = sessionId.trim();
    final normalizedRole = role.trim().toLowerCase();
    final messageText = text.trim();

    if (id.isEmpty || messageText.isEmpty || !isAuthenticated) {
      return false;
    }

    final outgoingMessageId = messageId?.trim().isNotEmpty == true
        ? messageId!.trim()
        : DateTime.now().microsecondsSinceEpoch.toString();

    final sentAt = DateTime.now().toUtc().toIso8601String();

    final localId = temp_e2ee.TemporarySignalE2eeService.identityForSession(
      id,
      normalizedRole,
    );

    final peerId = temp_e2ee.TemporarySignalE2eeService.peerIdentityForSession(
      id,
      normalizedRole,
    );

    final service = _temporaryE2eeServices.putIfAbsent(
      id,
      () => temp_e2ee.TemporarySignalE2eeService(),
    );

    await service.initializeForIdentity(localId);

    final privatePayload = <String, dynamic>{
      'sessionId': id,
      'messageId': outgoingMessageId,
      'time': sentAt,
      'text': messageText,
    };

    Map<String, dynamic> encrypted;

    try {
      encrypted = await service.encrypt(peerId, privatePayload);
    } on temp_e2ee.E2eeSessionMissing {
      final prepared = await _prepareTemporaryE2ee(id, normalizedRole);

      if (!prepared) {
        return false;
      }

      await _requestTemporaryE2eeBundle(id, normalizedRole);

      encrypted = await service.encrypt(peerId, privatePayload);
    }

    return _send('temporary_message', <String, dynamic>{
      'sessionId': id,
      'messageId': outgoingMessageId,
      'time': sentAt,
      ...encrypted,
    });
  }

  Future<bool> _prepareTemporaryE2ee(String sessionId, String role) async {
    final id = sessionId.trim();
    final normalizedRole = role.trim().toLowerCase();

    try {
      final localId = temp_e2ee.TemporarySignalE2eeService.identityForSession(
        id,
        normalizedRole,
      );

      final service = _temporaryE2eeServices.putIfAbsent(
        id,
        () => temp_e2ee.TemporarySignalE2eeService(),
      );

      await service.initializeForIdentity(localId);

      final bundle = await service.createPublicBundle();

      final previous = _temporaryE2eePublishRequests[id];
      if (previous != null && !previous.isCompleted) {
        previous.complete(false);
      }

      final request = Completer<bool>();
      _temporaryE2eePublishRequests[id] = request;

      if (!_send('temporary_e2ee_bundle_publish', {
        'sessionId': id,
        ...bundle,
      })) {
        _temporaryE2eePublishRequests.remove(id);
        throw StateError('Нет соединения с сервером');
      }

      final accepted = await request.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (identical(_temporaryE2eePublishRequests[id], request)) {
            _temporaryE2eePublishRequests.remove(id);
          }
          return false;
        },
      );

      if (!accepted) {
        throw StateError('Временный E2EE bundle отклонён');
      }

      return true;
    } catch (error) {
      print('Temporary E2EE не удалось подготовить: $error');
      return false;
    }
  }

  Future<void> _requestTemporaryE2eeBundle(
    String sessionId,
    String role,
  ) async {
    final id = sessionId.trim();
    final normalizedRole = role.trim().toLowerCase();

    final existing = _temporaryE2eeBundleRequests[id];
    if (existing != null) {
      await existing.future;
      return;
    }

    final localId = temp_e2ee.TemporarySignalE2eeService.identityForSession(
      id,
      normalizedRole,
    );

    final peerId = temp_e2ee.TemporarySignalE2eeService.peerIdentityForSession(
      id,
      normalizedRole,
    );

    final service = _temporaryE2eeServices.putIfAbsent(
      id,
      () => temp_e2ee.TemporarySignalE2eeService(),
    );

    await service.initializeForIdentity(localId);

    final request = Completer<Map<String, dynamic>>();
    _temporaryE2eeBundleRequests[id] = request;

    if (!_send('temporary_e2ee_bundle_get', {'sessionId': id})) {
      _temporaryE2eeBundleRequests.remove(id);
      throw StateError('Нет соединения с сервером');
    }

    final bundle = await request.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _temporaryE2eeBundleRequests.remove(id);
        throw TimeoutException(
          'Запрос ключей временного контакта превысил время ожидания',
        );
      },
    );

    await service.processRemoteBundle(peerId, bundle);
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

  Future<void> _migrateLegacyRatchetSessionsOnce() async {
    try {
      final user = currentUser?.trim() ?? '';
      if (user.isEmpty) return;
      final settings = E2eeSettingsService.instance;
      if (await settings.hasCompletedRatchetMigration(
        user,
        _ratchetSessionMigration,
      )) {
        return;
      }
      await SignalE2eeService.instance.initializeForUser(user);
      final deleted = await SignalE2eeService.instance
          .resetAllRatchetSessions();
      await settings.markRatchetMigrationCompleted(
        user,
        _ratchetSessionMigration,
      );
      print('🔐 Signal E2EE: обновлены сессии ($deleted)');
    } catch (error) {
      print('🔒 Signal E2EE: миграция сессий не выполнена ($error)');
    }
  }

  Future<bool> refreshPeerE2eeSession(String username) async {
    final user = currentUser?.trim() ?? '';
    final peer = username.trim();
    if (user.isEmpty || peer.isEmpty || !isAuthenticated) return false;
    try {
      await SignalE2eeService.instance.initializeForUser(user);
      await SignalE2eeService.instance.resetPeerRatchetSession(peer);
      await _requestE2eeBundle(peer);
      return await SignalE2eeService.instance.hasSession(peer);
    } catch (error) {
      print('🔒 E2EE: не удалось обновить сессию с $peer ($error)');
      return false;
    }
  }

  Future<Map<String, dynamic>> _requestContinuityDirectory(
    String peer,
    int epoch,
  ) async {
    if (!isAuthenticated || _continuityRequests.containsKey(peer))
      throw StateError('Continuity request unavailable');
    final generation = _connectionGeneration,
        channel = _channel,
        owner = currentUser;
    final id = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final result = Completer<Map<String, dynamic>>();
    _continuityRequests[peer] = (id: id, epoch: epoch, result: result);
    try {
      if (!_send('device_transfer_get_certificates_v2', {
        'username': peer,
        'fromEpoch': epoch,
        'requestId': id,
      }))
        throw StateError('Continuity request not sent');
      final data = await result.future.timeout(const Duration(seconds: 10));
      if (!isAuthenticated ||
          currentUser != owner ||
          generation != _connectionGeneration ||
          !identical(channel, _channel))
        throw StateError('Continuity response owner changed');
      return data;
    } finally {
      if (_continuityRequests[peer]?.id == id) _continuityRequests.remove(peer);
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
        'autoDeleteAfterReadSeconds':
            localMessage['autoDeleteAfterReadSeconds'] ?? 0,
        'autoDeleteUnreadSeconds': localMessage['autoDeleteUnreadSeconds'] ?? 0,
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
    'autoDeleteAfterReadSeconds': message['autoDeleteAfterReadSeconds'] ?? 0,
    'autoDeleteUnreadSeconds': message['autoDeleteUnreadSeconds'] ?? 0,
    if (message['replyTo'] is Map) 'replyTo': message['replyTo'],
    if (message['forwardedFrom'] != null)
      'forwardedFrom': message['forwardedFrom'],
    if (message['forwardComment'] != null)
      'forwardComment': message['forwardComment'],
    if (message['messageType'] != null) 'messageType': message['messageType'],
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
    final protectWithE2ee = isE2eeActiveWith(target);
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
    final protectWithE2ee = isE2eeActiveWith(target);
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

  void editMessage({
    required String messageId,
    required String to,
    required String newText,
  }) {
    final id = messageId.trim();
    final target = to.trim();
    final text = newText.trim();
    if (id.isEmpty || target.isEmpty || text.isEmpty) return;
    unawaited(_sendE2eeEditMessage(messageId: id, to: target, newText: text));
  }

  Future<void> _sendE2eeEditMessage({
    required String messageId,
    required String to,
    required String newText,
  }) async {
    final user = currentUser?.trim() ?? '';
    if (user.isEmpty || !isAuthenticated) return;
    try {
      await SignalE2eeService.instance.initializeForUser(user);
      final payload = <String, dynamic>{
        'kind': 'edit_message',
        'messageId': messageId,
        'from': user,
        'to': to,
        'newText': newText,
        'editedAt': DateTime.now().toIso8601String(),
      };
      Map<String, dynamic> encrypted;
      try {
        encrypted = await SignalE2eeService.instance.encrypt(to, payload);
      } on E2eeSessionMissing {
        await _requestE2eeBundle(to);
        encrypted = await SignalE2eeService.instance.encrypt(to, payload);
      }
      if (!_send('e2ee_edit_message', {
        'messageId': messageId,
        'to': to,
        ...encrypted,
      })) {
        throw StateError('Нет соединения с сервером');
      }
    } catch (error) {
      print('🔒 E2EE: редактирование не отправлено');
    }
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
    if (id.isEmpty || cleanText.isEmpty) return;
    _send('support_ai_request', {'requestId': id, 'text': cleanText});
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

  Future<bool> _sendProtectedCallSignal(
    String type, {
    required String to,
    required String callId,
    required Map<String, dynamic> clear,
  }) async {
    final peer = to.trim();
    final id = callId.trim();
    final user = currentUser?.trim() ?? '';
    if (peer.isEmpty || id.isEmpty || user.isEmpty) return false;
    try {
      await SignalE2eeService.instance.initializeForUser(user);
      final payload = <String, dynamic>{
        'kind': type,
        'callId': id,
        'from': user,
        'to': peer,
        ...clear,
      };
      Map<String, dynamic> encrypted;
      try {
        encrypted = await SignalE2eeService.instance.encrypt(peer, payload);
      } on E2eeSessionMissing {
        await _requestE2eeBundle(peer);
        encrypted = await SignalE2eeService.instance.encrypt(peer, payload);
      }
      return _send(type, {
        'to': peer,
        'callId': id,
        if (clear['video'] != null) 'video': clear['video'],
        'e2eeCall': encrypted,
      });
    } catch (_) {
      print('🔒 E2EE CALL: защищённый сигнал не отправлен');
      return false;
    }
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
    _clearTransferConnectionState();
    ++_connectionGeneration;
    _authenticated = false;
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

    for (final request in _temporaryE2eePublishRequests.values) {
      if (!request.isCompleted) {
        request.complete(false);
      }
    }
    _temporaryE2eePublishRequests.clear();

    for (final request in _temporaryE2eeBundleRequests.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('Connection to server closed'));
      }
    }
    _temporaryE2eeBundleRequests.clear();

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
