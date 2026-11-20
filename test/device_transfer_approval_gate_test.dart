import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval_gate.dart';

const aid = '11111111-1111-4111-8111-111111111111';

class Fixture {
  final old = IdentityKeyPair.generate();
  final fresh = IdentityKeyPair.generate();
  final gate = DeviceTransferApprovalGate();
  late Map<String, dynamic> challenge;
  late Map<String, dynamic> payload;
  late String signature;
  void initialize() {
    final out = Platform.environment['FENYVO_OUT']!;
    final result = Process.runSync(Platform.isWindows ? 'node.exe' : 'node', [
      out + Platform.pathSeparator + 'make_challenge.js',
      Directory.current.path +
          Platform.pathSeparator +
          'server_device_transfer_challenges.js',
      jsonEncode({
        'username': 'Alice',
        'accountId': aid,
        'hash': sha256.convert(fresh.publicKey).toString(),
      }),
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final reply = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    expect(reply['replayRejected'], isTrue);
    challenge = Map<String, dynamic>.from(reply['challenge'] as Map);
    bind();
  }

  String sign(Map<String, dynamic> data) => signDeviceTransferApproval(
    payload: data,
    identity: old,
    accountId: aid,
    username: 'Alice',
    newIdentityKey: fresh.publicKey,
    nonce: data['nonce'] as String,
    nowMs: 1001,
  );
  void bind() {
    payload = {
      ...challenge,
      'username': 'Alice',
      'oldIdentityHash': sha256.convert(old.publicKey).toString(),
      'newIdentityKey': base64Encode(fresh.publicKey),
    };
    signature = sign(payload);
    gate.begin(
      challenge: challenge,
      isAuthenticated: true,
      accountId: aid,
      username: 'Alice',
      trustedOldIdentityKey: old.publicKey,
      newIdentityKey: fresh.publicKey,
      connectionGeneration: 7,
      nowMs: 1001,
    );
  }

  VerifiedDeviceTransferApproval? accept({
    Map<String, dynamic>? data,
    String? sig,
    bool authenticated = true,
    String accountId = aid,
    String username = 'Alice',
    int generation = 7,
    int now = 1001,
  }) => gate.accept(
    payload: data ?? payload,
    signature: sig ?? signature,
    isAuthenticated: authenticated,
    currentAccountId: accountId,
    currentUsername: username,
    connectionGeneration: generation,
    nowMs: now,
  );
  void dispose() {
    fresh.dispose();
    old.dispose();
  }
}

void fixture(void Function(Fixture) run) {
  final f = Fixture();
  try {
    f.initialize();
    run(f);
  } finally {
    f.dispose();
  }
}

void main() {
  setUpAll(() async {
    await LibSignal.init();
  });
  test(
    'real Node challenge and Signal approval are accepted once',
    () => fixture((f) {
      final result = f.accept();
      expect(result, isNotNull);
      final accepted = result!;
      expect(accepted.payload['accountId'], aid);
      expect(
        () => accepted.payload['username'] = 'Bob',
        throwsUnsupportedError,
      );
      expect(f.accept(), isNull);
    }),
  );
  test(
    'invalid signature produces no verified result',
    () => fixture((f) {
      expect(f.accept(sig: 'invalid'), isNull);
      expect(f.accept(), isNotNull);
    }),
  );
  test('changed active account session or authentication revokes request', () {
    for (final mode in [
      'account',
      'username',
      'generation',
      'authentication',
    ]) {
      fixture((f) {
        expect(
          f.accept(
            accountId: mode == 'account'
                ? '22222222-2222-4222-8222-222222222222'
                : aid,
            username: mode == 'username' ? 'Bob' : 'Alice',
            generation: mode == 'generation' ? 8 : 7,
            authenticated: mode != 'authentication',
          ),
          isNull,
        );
        expect(f.accept(), isNull);
      });
    }
  });
  test(
    'signed lifetime cannot replace original challenge lifetime',
    () => fixture((f) {
      final changed = {...f.payload, 'expiresAt': 121001};
      expect(f.accept(data: changed, sig: f.sign(changed)), isNull);
    }),
  );
  test(
    'expired request cannot return after clock rollback',
    () => fixture((f) {
      expect(f.accept(now: 121000), isNull);
      expect(f.accept(), isNull);
    }),
  );
  test(
    'different signed nonce rejected',
    () => fixture((f) {
      final changed = {...f.payload, 'nonce': 'c' * 64};
      expect(f.accept(data: changed, sig: f.sign(changed)), isNull);
    }),
  );
  test(
    'three invalid attempts revoke request',
    () => fixture((f) {
      for (var i = 0; i < 3; i++) {
        expect(f.accept(sig: 'invalid'), isNull);
      }
      expect(f.accept(), isNull);
    }),
  );
  test(
    'clear revokes request',
    () => fixture((f) {
      f.gate.clear();
      expect(f.accept(), isNull);
    }),
  );
  test(
    'new request supersedes previous request',
    () => fixture((f) {
      final previous = f.payload, oldSignature = f.signature;
      f.challenge = {...f.challenge, 'nonce': 'd' * 64};
      f.bind();
      expect(f.accept(data: previous, sig: oldSignature), isNull);
      expect(f.accept(), isNotNull);
    }),
  );
  test(
    'input mutation cannot replace pinned keys or challenge',
    () => fixture((f) {
      final oldKey = List<int>.from(f.old.publicKey),
          newKey = List<int>.from(f.fresh.publicKey),
          copy = Map<String, dynamic>.from(f.challenge);
      f.gate.begin(
        challenge: copy,
        isAuthenticated: true,
        accountId: aid,
        username: 'Alice',
        trustedOldIdentityKey: oldKey,
        newIdentityKey: newKey,
        connectionGeneration: 7,
        nowMs: 1001,
      );
      oldKey[1] ^= 1;
      newKey[1] ^= 1;
      copy['nonce'] = 'e' * 64;
      expect(f.accept(), isNotNull);
    }),
  );
}
