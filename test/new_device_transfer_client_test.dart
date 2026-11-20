import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/new_device_transfer_client.dart';
import 'package:fenyvo/services/crypto/old_device_pin.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval.dart';

const id = '11111111-1111-4111-8111-111111111111';
Future<NewDeviceTransferPhase> terminal(NewDeviceTransferClient client) async {
  bool done() => [
    NewDeviceTransferPhase.failed,
    NewDeviceTransferPhase.verified,
    NewDeviceTransferPhase.cancelled,
  ].contains(client.phase);
  if (done()) return client.phase;
  final result = Completer<NewDeviceTransferPhase>();
  void listener() {
    if (done() && !result.isCompleted) result.complete(client.phase);
  }

  client.addListener(listener);
  try {
    return await result.future.timeout(const Duration(seconds: 5));
  } finally {
    client.removeListener(listener);
  }
}

Future<void> fixture(
  String mode,
  Future<void> Function(NewDeviceTransferClient) check,
) async {
  final old = IdentityKeyPair.generate(),
      fresh = IdentityKeyPair.generate(),
      impostor = IdentityKeyPair.generate();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  WebSocket? peer;
  StreamSubscription<dynamic>? peerEvents;
  var closing = false;
  final subscription = server.listen((request) async {
    final ws = await WebSocketTransformer.upgrade(request);
    if (closing) {
      await ws.close();
      return;
    }
    peer = ws;
    ws.add(jsonEncode({'type': 'connected', 'data': {}}));
    peerEvents = ws.listen((raw) {
      if (closing) return;
      final event = jsonDecode(raw as String) as Map;
      if (event['type'] == 'ping') {
        ws.add(jsonEncode({'type': 'pong', 'data': {}}));
        return;
      }
      if (event['type'] != 'login') return;
      expect((event['data'] as Map)['mode'], 'device_transfer_prepare');
      if (mode == 'login_success' || mode == 'login_error') {
        ws.add(jsonEncode({'type': mode, 'data': {}}));
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final challenge = {
        'purpose': 'fenyvo-device-transfer-v1',
        'accountId': id,
        'username': 'Alice',
        'candidateHash': sha256.convert(fresh.publicKey).toString(),
        'newIdentityKey': base64Encode(fresh.publicKey),
        'nonce': 'b' * 64,
        'issuedAt': now - 1,
        'expiresAt': now + 120000,
      };
      final pending = {...challenge};
      if (mode == 'wrong_account')
        pending['accountId'] = '22222222-2222-4222-8222-222222222222';
      if (mode == 'wrong_candidate')
        pending['newIdentityKey'] = base64Encode(impostor.publicKey);
      ws.add(jsonEncode({'type': 'device_transfer_pending', 'data': pending}));
      if (mode == 'cancel') return;
      final signer = mode == 'wrong_old_key' ? impostor : old;
      final payload = {
        ...challenge,
        'oldIdentityHash': sha256.convert(signer.publicKey).toString(),
      };
      if (mode == 'changed_lifetime')
        payload['expiresAt'] = (payload['expiresAt'] as int) + 1;
      var signature = signDeviceTransferApproval(
        payload: payload,
        identity: signer,
        accountId: id,
        username: 'Alice',
        newIdentityKey: fresh.publicKey,
        nonce: 'b' * 64,
        nowMs: now,
      );
      if (mode == 'bad_signature') signature = base64Encode(List.filled(64, 0));
      ws.add(
        jsonEncode({
          'type': 'device_transfer_proof_unverified',
          'data': {'payload': payload, 'signature': signature},
        }),
      );
    }, onError: (_) {});
  });
  final pin = OldDevicePin.create(
    accountId: id,
    username: 'Alice',
    publicKey: old.publicKey,
  );
  final client = NewDeviceTransferClient(
    server: Uri.parse('ws://127.0.0.1:' + server.port.toString()),
    pin: pin,
    candidatePublicKey: fresh.publicKey,
  );
  try {
    await client.start(password: 'test-password');
    await check(client);
  } finally {
    closing = true;
    client.dispose();
    await peerEvents?.cancel();
    await peer?.close();
    await subscription.cancel();
    await server.close(force: true);
    old.dispose();
    fresh.dispose();
    impostor.dispose();
  }
}

Future<void> waitForPending(NewDeviceTransferClient c) async {
  if (c.phase == NewDeviceTransferPhase.awaitingOldDevice) return;
  if (c.phase == NewDeviceTransferPhase.failed)
    throw StateError('Preparation failed');
  final ready = Completer<void>();
  void listener() {
    if (ready.isCompleted) return;
    if (c.phase == NewDeviceTransferPhase.awaitingOldDevice)
      ready.complete();
    else if (c.phase == NewDeviceTransferPhase.failed)
      ready.completeError(StateError('Preparation failed'));
  }

  c.addListener(listener);
  try {
    await ready.future.timeout(const Duration(seconds: 5));
  } finally {
    c.removeListener(listener);
  }
}

void main() {
  setUpAll(() async {
    await LibSignal.init();
  });
  test(
    'separate pending channel verifies pinned old signature without login',
    () async {
      await fixture('valid', (c) async {
        expect(await terminal(c), NewDeviceTransferPhase.verified);
        expect(c.verifiedProof, isNotNull);
        expect(
          () => c.verifiedProof!['signature'] = 'other',
          throwsUnsupportedError,
        );
        expect(
          () => c.verifiedProof!['payload']['username'] = 'Bob',
          throwsUnsupportedError,
        );
      });
    },
  );
  for (final mode in [
    'wrong_old_key',
    'changed_lifetime',
    'bad_signature',
    'wrong_account',
    'wrong_candidate',
    'login_success',
    'login_error',
  ]) {
    test('fails closed for ' + mode, () async {
      await fixture(mode, (c) async {
        expect(await terminal(c), NewDeviceTransferPhase.failed);
        expect(c.verifiedProof, isNull);
      });
    });
  }
  test(
    'cancellation terminates pending channel and cannot restart it',
    () async {
      await fixture('cancel', (c) async {
        await waitForPending(c);
        c.cancel();
        expect(c.phase, NewDeviceTransferPhase.cancelled);
        expect(c.verifiedProof, isNull);
        await expectLater(c.start(password: 'test'), throwsStateError);
      });
    },
  );
  test(
    'rejects unencrypted non-loopback server without network connection',
    () async {
      final key = [5, ...List.filled(32, 1)],
          pin = OldDevicePin.create(
            accountId: id,
            username: 'Alice',
            publicKey: key,
          );
      final c = NewDeviceTransferClient(
        server: Uri.parse('ws://example.invalid/ws'),
        pin: pin,
        candidatePublicKey: key,
      );
      try {
        await c.start(password: 'test');
        expect(c.phase, NewDeviceTransferPhase.failed);
      } finally {
        c.dispose();
      }
    },
  );
  test('cancellation from connecting listener creates no socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    final subscription = server.listen((request) {
      connections++;
      request.response.close();
    });
    final key = [5, ...List.filled(32, 1)],
        pin = OldDevicePin.create(
          accountId: id,
          username: 'Alice',
          publicKey: key,
        );
    final c = NewDeviceTransferClient(
      server: Uri.parse('ws://127.0.0.1:' + server.port.toString()),
      pin: pin,
      candidatePublicKey: key,
    );
    c.addListener(() {
      if (c.phase == NewDeviceTransferPhase.connecting) c.cancel();
    });
    try {
      await c.start(password: 'test');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.phase, NewDeviceTransferPhase.cancelled);
      expect(connections, 0);
    } finally {
      c.dispose();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
