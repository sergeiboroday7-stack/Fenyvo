import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto/device_transfer_approval.dart';
import 'crypto/device_transfer_request.dart';
import 'crypto/device_key_transition.dart';
import 'crypto/device_transfer_candidate_store.dart';
import 'crypto/old_device_pin.dart';
import 'crypto/signal_e2ee_service.dart';
import 'device_transfer_diagnostics.dart';

enum TransferV2Phase {
  idle,
  staging,
  waiting,
  committing,
  recovering,
  activating,
  publishing,
  ready,
  interrupted,
}

/// Injectable transport; credentials are never retained in a field or journal.
abstract interface class TransferV2Wire {
  Future<void> open(Uri server);
  void send(String type, Map<String, dynamic> data);
  Future<Map<String, dynamic>> receive();
  Future<void> close();
}

class WebSocketTransferV2Wire implements TransferV2Wire {
  WebSocketChannel? _channel;
  StreamIterator<dynamic>? _messages;
  bool _closed = false, _claimed = false;
  WebSocketChannel get activeChannel =>
      _channel ?? (throw StateError("No transfer channel"));
  @override
  Future<void> open(Uri server) async {
    if (_closed) throw StateError('Transport closed');
    final channel = WebSocketChannel.connect(server);
    _channel = channel;
    _messages = StreamIterator<dynamic>(channel.stream);
    await channel.ready.timeout(const Duration(seconds: 15));
  }

  @override
  void send(String type, Map<String, dynamic> data) {
    if (_closed || _channel == null) throw StateError('Transport unavailable');
    _channel!.sink.add(jsonEncode({'type': type, 'data': data}));
  }

  @override
  Future<Map<String, dynamic>> receive() async {
    final messages = _messages;
    if (messages == null || !await messages.moveNext())
      throw StateError('Transport ended');
    final raw = messages.current;
    if (raw is! String || raw.length > 65536)
      throw StateError('Invalid transfer frame');
    final frame = jsonDecode(raw);
    if (frame is! Map<String, dynamic> ||
        frame['type'] is! String ||
        frame['data'] is! Map)
      throw StateError('Invalid transfer frame');
    return {
      'type': frame['type'],
      'data': Map<String, dynamic>.from(frame['data'] as Map),
    };
  }

  @override
  Future<void> close() async {
    if (_claimed) return;
    _closed = true;
    try {
      await _messages?.cancel();
    } catch (_) {}
    try {
      await _channel?.sink.close();
    } catch (_) {}
  }
}

/// Isolated v2 protocol. Does not route chat messages or enable the feature UI.
/// A fresh instance resumes the sealed candidate after any uncertain response.
class NewDeviceTransferV2Client extends ChangeNotifier {
  NewDeviceTransferV2Client({
    required this.server,
    required this.pin,
    TransferV2Wire? wire,
    this.responseTimeout = const Duration(seconds: 150),
  }) : _wire = wire ?? WebSocketTransferV2Wire(),
       store = DeviceTransferCandidateStore(pin.username);
  final Uri server;
  final OldDevicePin pin;
  final DeviceTransferCandidateStore store;
  final TransferV2Wire _wire;
  final Duration responseTimeout;
  TransferV2Phase phase = TransferV2Phase.idle;
  TransferFailure? failure;
  TransferDiagnosticStage _diagnosticStage =
      TransferDiagnosticStage.validating;
  PendingTransferCandidate? candidate;
  bool _stopped = false, _disposed = false;
  Timer? _heartbeat, _handoffLease;
  Map<String, dynamic>? _activationData;
  final List<Map<String, dynamic>> _incoming = [];
  int _incomingBytes = 0;
  bool _connectionTaken = false;
  TransferredDeviceConnection takeConnection() {
    _check();
    if (phase != TransferV2Phase.ready ||
        _connectionTaken ||
        _activationData == null ||
        _wire is! WebSocketTransferV2Wire)
      throw StateError('Verified connection unavailable');
    final wire = _wire;
    if (wire._closed || wire._claimed)
      throw StateError('Transfer channel already closed or claimed');
    wire._claimed = true;
    _connectionTaken = true;
    _handoffLease?.cancel();
    return TransferredDeviceConnection._(wire, server, pin.username, [
      {'type': 'login_success', 'data': _activationData},
      ..._incoming,
    ]);
  }

  bool get _current => !_stopped && !_disposed;
  void _check() {
    if (!_current) throw StateError('Transfer operation stopped');
  }

  void _phase(TransferV2Phase value) {
    _check();
    phase = value;
    notifyListeners();
    _check();
  }

  void _send(String type, Map<String, dynamic> data) {
    _check();
    _wire.send(type, data);
  }

  Future<Map<String, dynamic>> _next(String expected) async {
    final end = DateTime.now().add(responseTimeout);
    while (true) {
      _check();
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero)
        throw TimeoutException('Transfer response deadline');
      final frame = await _wire.receive().timeout(remaining);
      _check();
      final type = frame['type'], data = frame['data'];
      if (data is! Map<String, dynamic>)
        throw StateError('Invalid transfer response');
      if (type == 'ping') {
        _send('pong', {});
        continue;
      }
      if (type == 'pong' || type == 'connected') continue;
      if (type != expected) {
        if (_activationData == null ||
            type is! String ||
            type.startsWith('device_transfer_') ||
            type == 'login_success' ||
            type == 'login_error' ||
            type == 'error' ||
            type == 'disconnected' ||
            type == 'rate_limited')
          throw StateError('Unexpected transfer response');
        _incomingBytes += utf8.encode(jsonEncode(frame)).length;
        if (_incoming.length >= 128 || _incomingBytes > 1048576)
          throw StateError('Activation incoming queue limit exceeded');
        _incoming.add(jsonDecode(jsonEncode(frame)) as Map<String, dynamic>);
        continue;
      }
      return data;
    }
  }

  Map<String, dynamic> _login(String password, String mode) => {
    'username': pin.username,
    'password': password,
    'mode': mode,
    'newIdentityKey': candidate!.identityKey,
    if (candidate!.transferNonce != null)
      'transferNonce': candidate!.transferNonce,
  };
  Future<void> run({required String password}) async {
    if (phase != TransferV2Phase.idle || !_current)
      throw StateError('Create a fresh client to resume');
    try {
      final local = {'localhost', '127.0.0.1', '::1'}.contains(server.host);
      if (server.host.isEmpty ||
          server.userInfo.isNotEmpty ||
          server.hasFragment ||
          (server.scheme != 'wss' && !(server.scheme == 'ws' && local)) ||
          password.isEmpty ||
          password.length > 128)
        throw StateError('Invalid transfer endpoint or credentials');
      _phase(TransferV2Phase.staging);
      _diagnosticStage = TransferDiagnosticStage.localProfile;
      candidate = await store.createOrResume(
        pin,
        isOperationCurrent: () => _current,
      );
      _check();
      _diagnosticStage = TransferDiagnosticStage.connecting;
      await _wire.open(server);
      _check();
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_current) {
          try {
            _send('ping', {});
          } catch (_) {
            unawaited(cancel());
          }
        }
      });
      if (candidate!.phase != 'staged') {
        _phase(TransferV2Phase.recovering);
        final nonce = candidate!.transferNonce!;
        _diagnosticStage = TransferDiagnosticStage.recovering;
        _send('login', _login(password, 'device_transfer_status_v2'));
        final status = await _next('device_transfer_status_v2');
        if (status['committed'] == false) {
          candidate = await store.resetAfterUncommittedStatus(
            status,
            expectedTransferNonce: nonce,
            isOperationCurrent: () => _current,
          );
          // New prepare requires a new socket/context. Never automatically regenerate a key.
          throw StateError(
            'Uncommitted attempt resolved; resume the same candidate',
          );
        }
        candidate = await store.observeCommit(
          status,
          expectedTransferNonce: nonce,
          fromStatus: true,
          isOperationCurrent: () => _current,
        );
        _check();
      } else {
        _diagnosticStage = TransferDiagnosticStage.requesting;
        _send('login', _login(password, 'device_transfer_prepare_v2'));
        final request = DeviceTransferRequest.parseV2(
          await _next('device_transfer_pending_v2'),
          accountId: pin.accountId,
          username: pin.username,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (request == null ||
            base64Encode(request.newIdentityKey) != candidate!.identityKey)
          throw StateError('Candidate challenge differs');
        _diagnosticStage = TransferDiagnosticStage.waitingForApproval;
        _phase(TransferV2Phase.waiting);
        final proof = await _next('device_transfer_proof_v2_unverified');
        _diagnosticStage = TransferDiagnosticStage.verifying;
        if (proof.length != 2 ||
            proof['approval'] is! Map ||
            proof['certificate'] is! Map)
          throw StateError('Invalid proof envelope');
        final approval = Map<String, dynamic>.from(proof['approval'] as Map),
            certificate = Map<String, dynamic>.from(
              proof['certificate'] as Map,
            );
        if (approval.length != 2 ||
            certificate.length != 2 ||
            approval['payload'] is! Map ||
            approval['signature'] is! String ||
            certificate['payload'] is! Map ||
            certificate['signature'] is! String)
          throw StateError('Invalid proof');
        final payload = Map<String, dynamic>.from(approval['payload'] as Map),
            cert = Map<String, dynamic>.from(certificate['payload'] as Map),
            now = DateTime.now().millisecondsSinceEpoch;
        if (!request.validAt(now) ||
            payload['issuedAt'] != request.data['issuedAt'] ||
            payload['expiresAt'] != request.expiresAt ||
            !verifyDeviceTransferApproval(
              payload: payload,
              signature: approval['signature'] as String,
              trustedOldIdentityKey: pin.publicKey,
              accountId: pin.accountId,
              username: pin.username,
              newIdentityKey: request.newIdentityKey,
              nonce: request.nonce,
              nowMs: now,
            ) ||
            cert['transferNonce'] != request.nonce ||
            cert['issuedAt'] != request.data['issuedAt'])
          throw StateError('Approval not bound to current request');
        final verified = verifyDeviceKeyTransition(
          payload: cert,
          signature: certificate['signature'] as String,
          trustedOldIdentityKey: pin.publicKey,
          accountId: pin.accountId,
          username: pin.username,
          storedEpoch: request.fromEpoch!,
          nowMs: now,
        );
        if (verified == null ||
            base64Encode(verified.newIdentityKey) != candidate!.identityKey)
          throw StateError('Invalid transition signature');
        candidate = await store.recordVerifiedCertificate(
          verified,
          expectedTransferNonce: request.nonce,
          isOperationCurrent: () => _current,
        );
        _check();
        _diagnosticStage = TransferDiagnosticStage.committing;
        _phase(TransferV2Phase.committing);
        _send('device_transfer_commit_v2', {'transferNonce': request.nonce});
        candidate = await store.observeCommit(
          await _next('device_transfer_committed_v2'),
          expectedTransferNonce: request.nonce,
          fromStatus: false,
          isOperationCurrent: () => _current,
        );
        _check();
      }
      final nonce = candidate!.transferNonce!;
      _phase(TransferV2Phase.activating);
      _diagnosticStage = TransferDiagnosticStage.installing;
      candidate = await store.installForActivation(
        expectedTransferNonce: nonce,
        isOperationCurrent: () => _current,
      );
      _check();
      _diagnosticStage = TransferDiagnosticStage.activating;
      _send('login', _login(password, 'device_transfer_activate_v2'));
      final accepted = await _next('login_success');
      final epoch = (candidate!.publicData['receipt'] as Map)['epoch'];
      if (accepted['username'] != pin.username ||
          accepted['accountId'] != pin.accountId ||
          accepted['deviceTransferActivated'] != true ||
          accepted['deviceTransferEpoch'] != epoch)
        throw StateError('Activation context differs');
      _activationData = Map<String, dynamic>.from(accepted);
      _diagnosticStage = TransferDiagnosticStage.publishing;
      _phase(TransferV2Phase.publishing);
      final service = SignalE2eeService.instance;
      await service.initializeForUser(pin.username);
      _check();
      final bundle = await service.createPublicBundle();
      _check();
      if (bundle['identityKey'] != candidate!.identityKey)
        throw StateError('Activated bundle identity differs');
      _send('e2ee_publish_bundle', bundle);
      if ((await _next('e2ee_bundle_published'))['ok'] != true)
        throw StateError('Activated bundle was not persisted');
      _phase(TransferV2Phase.ready);
    } catch (error) {
      if (!_disposed) {
        failure = classifyTransferFailure(error, _diagnosticStage);
        phase = TransferV2Phase.interrupted;
        notifyListeners();
      }
    } finally {
      _heartbeat?.cancel();
      if (phase == TransferV2Phase.ready &&
          _wire is WebSocketTransferV2Wire &&
          !_stopped &&
          !_disposed) {
        if (!_connectionTaken)
          _handoffLease = Timer(const Duration(seconds: 30), () {
            unawaited(cancel());
          });
      } else {
        await _wire.close();
      }
    }
  }

  Future<void> cancel() async {
    _stopped = true;
    _handoffLease?.cancel();
    _heartbeat?.cancel();
    await _wire.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}

/// Single-owner continuation of the SAME authenticated WebSocket.
/// Created only after the native v2 protocol and bundle ACK succeed.
class TransferredDeviceConnection {
  TransferredDeviceConnection._(
    this._wire,
    this.server,
    this.username,
    List<Map<String, dynamic>> initial,
  ) : _initial = List<Map<String, dynamic>>.from(
        jsonDecode(jsonEncode(initial)) as List,
      );
  final WebSocketTransferV2Wire _wire;
  final Uri server;
  final String username;
  final List<Map<String, dynamic>> _initial;
  bool _consumed = false, _aborted = false;
  WebSocketChannel get channel {
    if (_aborted) throw StateError("Transfer connection closed");
    return _wire.activeChannel;
  }

  Future<void> drain(Future<void> Function(dynamic) accept) async {
    if (_consumed || _aborted)
      throw StateError('Transfer connection already consumed or closed');
    _consumed = true;
    try {
      for (final frame in _initial) {
        await accept(jsonEncode(frame));
      }
      _initial.clear();
      final messages = _wire._messages!;
      while (await messages.moveNext()) {
        await accept(messages.current);
      }
    } finally {
      await abort();
    }
  }

  Future<void> abort() async {
    _aborted = true;
    try {
      await _wire._messages?.cancel();
    } catch (_) {}
    try {
      await _wire.activeChannel.sink.close();
    } catch (_) {}
  }
}
