import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval.dart';

const aid = '11111111-1111-4111-8111-111111111111';
final nonce = 'a' * 64;
void fixture(
  void Function(IdentityKeyPair, IdentityKeyPair, Map<String, dynamic>) run,
) {
  final old = IdentityKeyPair.generate(), fresh = IdentityKeyPair.generate();
  final payload = <String, dynamic>{
    'purpose': 'fenyvo-device-transfer-v1',
    'accountId': aid,
    'username': 'Alice',
    'oldIdentityHash': sha256.convert(old.publicKey).toString(),
    'newIdentityKey': base64Encode(fresh.publicKey),
    'candidateHash': sha256.convert(fresh.publicKey).toString(),
    'nonce': nonce,
    'issuedAt': 1000,
    'expiresAt': 121000,
  };
  try {
    run(old, fresh, payload);
  } finally {
    fresh.dispose();
    old.dispose();
  }
}

String sign(
  Map<String, dynamic> p,
  IdentityKeyPair old,
  IdentityKeyPair fresh,
) => signDeviceTransferApproval(
  payload: p,
  identity: old,
  accountId: aid,
  username: 'Alice',
  newIdentityKey: fresh.publicKey,
  nonce: nonce,
  nowMs: 1001,
);
bool verify(
  Map<String, dynamic> p,
  String sig,
  IdentityKeyPair old,
  IdentityKeyPair fresh, {
  int now = 1001,
  String accountId = aid,
  String username = 'Alice',
  String? requestNonce,
}) => verifyDeviceTransferApproval(
  payload: p,
  signature: sig,
  trustedOldIdentityKey: old.publicKey,
  accountId: accountId,
  username: username,
  newIdentityKey: fresh.publicKey,
  nonce: requestNonce ?? nonce,
  nowMs: now,
);
void main() {
  setUpAll(() async {
    await LibSignal.init();
  });
  test(
    'valid bound approval verifies',
    () => fixture((old, fresh, p) {
      expect(verify(p, sign(p, old, fresh), old, fresh), isTrue);
    }),
  );
  test(
    'changing any signed field rejects approval',
    () => fixture((old, fresh, p) {
      final sig = sign(p, old, fresh);
      final changes = <String, dynamic>{
        'purpose': 'another-purpose',
        'accountId': '22222222-2222-4222-8222-222222222222',
        'username': 'Bob',
        'oldIdentityHash': 'b' * 64,
        'newIdentityKey': base64Encode(old.publicKey),
        'candidateHash': 'b' * 64,
        'nonce': 'b' * 64,
        'issuedAt': 1001,
        'expiresAt': 121001,
      };
      for (final change in changes.entries) {
        expect(
          verify({...p, change.key: change.value}, sig, old, fresh),
          isFalse,
          reason: change.key,
        );
      }
    }),
  );
  test(
    'trusted old key cannot come from an attacker',
    () => fixture((old, fresh, p) {
      final attacker = IdentityKeyPair.generate();
      try {
        expect(verify(p, sign(p, old, fresh), attacker, fresh), isFalse);
      } finally {
        attacker.dispose();
      }
    }),
  );
  test(
    'expected account username and nonce are mandatory',
    () => fixture((old, fresh, p) {
      final sig = sign(p, old, fresh);
      expect(
        verify(
          p,
          sig,
          old,
          fresh,
          accountId: '22222222-2222-4222-8222-222222222222',
        ),
        isFalse,
      );
      expect(verify(p, sig, old, fresh, username: 'Bob'), isFalse);
      expect(verify(p, sig, old, fresh, requestNonce: 'b' * 64), isFalse);
    }),
  );
  test(
    'expiry and not-yet-valid approvals rejected',
    () => fixture((old, fresh, p) {
      final sig = sign(p, old, fresh);
      expect(verify(p, sig, old, fresh, now: 121000), isFalse);
      expect(verify(p, sig, old, fresh, now: 999), isFalse);
    }),
  );
  test(
    'map property order does not alter signed bytes',
    () => fixture((old, fresh, p) {
      final reversed = Map<String, dynamic>.fromEntries(
        p.entries.toList().reversed,
      );
      expect(verify(reversed, sign(p, old, fresh), old, fresh), isTrue);
    }),
  );
  test(
    'extra fields and invalid field types rejected',
    () => fixture((old, fresh, p) {
      final sig = sign(p, old, fresh);
      expect(verify({...p, 'extra': 'unsigned'}, sig, old, fresh), isFalse);
      expect(verify({...p, 'issuedAt': 1000.0}, sig, old, fresh), isFalse);
      expect(verify({...p, 'expiresAt': 400001}, sig, old, fresh), isFalse);
    }),
  );
  test(
    'modified and noncanonical signatures rejected',
    () => fixture((old, fresh, p) {
      final sig = sign(p, old, fresh), bytes = base64Decode(sig);
      bytes[0] ^= 1;
      expect(verify(p, base64Encode(bytes), old, fresh), isFalse);
      expect(verify(p, sig + '\n', old, fresh), isFalse);
      expect(verify(p, 'invalid', old, fresh), isFalse);
    }),
  );
  test(
    'different expected target identity rejects approval',
    () => fixture((old, fresh, p) {
      final other = IdentityKeyPair.generate();
      try {
        expect(verify(p, sign(p, old, fresh), old, other), isFalse);
      } finally {
        other.dispose();
      }
    }),
  );
  test(
    'signer refuses a payload outside its account context',
    () => fixture((old, fresh, p) {
      expect(
        () => sign({...p, 'username': 'Bob'}, old, fresh),
        throwsStateError,
      );
      expect(
        () => sign({...p, 'oldIdentityHash': 'b' * 64}, old, fresh),
        throwsStateError,
      );
    }),
  );
}
