import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto/device_transfer_approval.dart';
import 'crypto/device_transfer_request.dart';
import 'crypto/old_device_pin.dart';

enum NewDeviceTransferPhase {
  idle,
  connecting,
  awaitingOldDevice,
  verified,
  failed,
  cancelled,
}

/// Separate pending channel. It never signs in, changes contacts or stores keys.
class NewDeviceTransferClient extends ChangeNotifier {
  NewDeviceTransferClient({
    required this.server,
    required this.pin,
    required List<int> candidatePublicKey,
  }) : _candidate = Uint8List.fromList(candidatePublicKey);
  final Uri server;
  final OldDevicePin pin;
  final Uint8List _candidate;
  NewDeviceTransferPhase phase = NewDeviceTransferPhase.idle;
  Map<String, dynamic>? verifiedProof;
  DeviceTransferRequest? request;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _deadline, _heartbeat;
  int _generation = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation, WebSocketChannel channel) =>
      !_disposed && generation == _generation && identical(channel, _channel);
  Future<void> _closeTransport() async {
    ++_generation;
    _deadline?.cancel();
    _heartbeat?.cancel();
    final subscription = _subscription, channel = _channel;
    _subscription = null;
    _channel = null;
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await channel?.sink.close();
    } catch (_) {}
  }

  void _fail() {
    if (_disposed ||
        phase == NewDeviceTransferPhase.verified ||
        phase == NewDeviceTransferPhase.cancelled)
      return;
    phase = NewDeviceTransferPhase.failed;
    request = null;
    verifiedProof = null;
    unawaited(_closeTransport());
    _notify();
  }

  Future<void> start({required String password}) async {
    if (_disposed || phase != NewDeviceTransferPhase.idle)
      throw StateError('Create a fresh transfer client');
    final loopback =
        server.host == '127.0.0.1' ||
        server.host == 'localhost' ||
        server.host == '::1';
    if (server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasFragment ||
        (server.scheme != 'wss' && !(server.scheme == 'ws' && loopback)) ||
        password.isEmpty ||
        password.length > 128 ||
        _candidate.length != 33 ||
        _candidate.first != 5) {
      _fail();
      return;
    }
    phase = NewDeviceTransferPhase.connecting;
    _notify();
    if (_disposed || phase != NewDeviceTransferPhase.connecting) return;
    final generation = ++_generation;
    try {
      final channel = WebSocketChannel.connect(server);
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) {
          if (_current(generation, channel)) _receive(raw, generation, channel);
        },
        onError: (_) {
          if (_current(generation, channel)) _fail();
        },
        onDone: () {
          if (_current(generation, channel)) _fail();
        },
      );
      _deadline = Timer(const Duration(seconds: 30), _fail);
      await channel.ready.timeout(const Duration(seconds: 15));
      if (!_current(generation, channel)) return;
      channel.sink.add(
        jsonEncode({
          'type': 'login',
          'data': {
            'username': pin.username,
            'password': password,
            'mode': 'device_transfer_prepare',
            'newIdentityKey': base64Encode(_candidate),
          },
        }),
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_current(generation, channel)) {
          try {
            channel.sink.add(jsonEncode({'type': 'ping', 'data': {}}));
          } catch (_) {
            _fail();
          }
        }
      });
    } catch (_) {
      if (!_disposed && generation == _generation) _fail();
    }
  }

  void _receive(dynamic raw, int generation, WebSocketChannel channel) {
    try {
      if (raw is! String || raw.length > 16384) {
        _fail();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _fail();
        return;
      }
      final type = decoded['type'], data = decoded['data'];
      if (type == 'ping') {
        channel.sink.add(jsonEncode({'type': 'pong', 'data': {}}));
        return;
      }
      if (type == 'pong') return;
      if (type == 'connected' && phase == NewDeviceTransferPhase.connecting)
        return;
      if (type == 'login_success' ||
          type == 'login_error' ||
          type == 'device_transfer_error' ||
          type == 'disconnected' ||
          type == 'rate_limited') {
        _fail();
        return;
      }
      if (type == 'device_transfer_pending') {
        if (phase != NewDeviceTransferPhase.connecting || data is! Map) {
          _fail();
          return;
        }
        final candidate = DeviceTransferRequest.parse(
          Map<String, dynamic>.from(data),
          accountId: pin.accountId,
          username: pin.username,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (candidate == null ||
            base64Encode(candidate.newIdentityKey) !=
                base64Encode(_candidate)) {
          _fail();
          return;
        }
        request = candidate;
        phase = NewDeviceTransferPhase.awaitingOldDevice;
        _deadline?.cancel();
        _deadline = Timer(
          Duration(
            milliseconds:
                candidate.expiresAt - DateTime.now().millisecondsSinceEpoch,
          ),
          _fail,
        );
        _notify();
        return;
      }
      if (type == 'device_transfer_proof_unverified') {
        final pending = request;
        if (phase != NewDeviceTransferPhase.awaitingOldDevice ||
            pending == null ||
            data is! Map ||
            data.length != 2 ||
            data['payload'] is! Map ||
            data['signature'] is! String) {
          _fail();
          return;
        }
        final payload = Map<String, dynamic>.from(data['payload'] as Map),
            signature = data['signature'] as String;
        if (payload['issuedAt'] != pending.data['issuedAt'] ||
            payload['expiresAt'] != pending.data['expiresAt'] ||
            !verifyDeviceTransferApproval(
              payload: payload,
              signature: signature,
              trustedOldIdentityKey: pin.publicKey,
              accountId: pin.accountId,
              username: pin.username,
              newIdentityKey: _candidate,
              nonce: pending.nonce,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            )) {
          _fail();
          return;
        }
        if (!_current(generation, channel)) return;
        verifiedProof = Map<String, dynamic>.unmodifiable({
          'payload': Map<String, dynamic>.unmodifiable(payload),
          'signature': signature,
        });
        phase = NewDeviceTransferPhase.verified;
        unawaited(_closeTransport());
        _notify();
        return;
      }
      // A pending channel has no legitimate chat, contact, media or group events.
      _fail();
    } catch (_) {
      _fail();
    }
  }

  void cancel() {
    if (_disposed) return;
    phase = NewDeviceTransferPhase.cancelled;
    request = null;
    verifiedProof = null;
    unawaited(_closeTransport());
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    request = null;
    verifiedProof = null;
    unawaited(_closeTransport());
    super.dispose();
  }
}
