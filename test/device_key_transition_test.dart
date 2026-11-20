import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/device_key_transition.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> payload(
  IdentityKeyPair old,
  IdentityKeyPair fresh, {
  int epoch = 0,
  int issued = 900,
  String nonce = 'b',
}) => {
  'purpose': 'fenyvo-device-key-transition-v1',
  'accountId': id,
  'username': 'Alice',
  'oldIdentityHash': sha256.convert(old.publicKey).toString(),
  'newIdentityKey': base64Encode(fresh.publicKey),
  'fromEpoch': epoch,
  'toEpoch': epoch + 1,
  'issuedAt': issued,
  'transferNonce': nonce * 64,
};
String sign(
  Map<String, dynamic> p,
  IdentityKeyPair old,
  IdentityKeyPair fresh, {
  bool confirmed = true,
  int epoch = 0,
  int now = 1000,
  String nonce = 'b',
}) => signDeviceKeyTransition(
  payload: p,
  identity: old,
  accountId: id,
  username: 'Alice',
  fromEpoch: epoch,
  newIdentityKey: fresh.publicKey,
  transferNonce: nonce * 64,
  nowMs: now,
  userConfirmed: confirmed,
);
VerifiedDeviceKeyTransition? verify(
  Map<String, dynamic> p,
  String signature,
  IdentityKeyPair old, {
  int epoch = 0,
  int now = 1000,
  String owner = 'Alice',
  String account = id,
}) => verifyDeviceKeyTransition(
  payload: p,
  signature: signature,
  trustedOldIdentityKey: old.publicKey,
  accountId: account,
  username: owner,
  storedEpoch: epoch,
  nowMs: now,
);
void fixture(
  void Function(IdentityKeyPair, IdentityKeyPair, IdentityKeyPair) body,
) {
  final old = IdentityKeyPair.generate(),
      fresh = IdentityKeyPair.generate(),
      next = IdentityKeyPair.generate();
  try {
    body(old, fresh, next);
  } finally {
    old.dispose();
    fresh.dispose();
    next.dispose();
  }
}

void main() {
  setUpAll(() async {
    await LibSignal.init();
  });
  test(
    'old pinned key signs the exact next identity and epoch',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), r = verify(p, sign(p, old, fresh), old)!;
      expect(r.toEpoch, 1);
      expect(r.newIdentityKey, fresh.publicKey);
    }),
  );
  test(
    'certificate remains verifiable for a contact reconnecting much later',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh);
      expect(
        verify(p, sign(p, old, fresh), old, now: 1000000000000),
        isNotNull,
      );
    }),
  );
  test(
    'every signed field is protected from tampering',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), signature = sign(p, old, fresh);
      for (final entry in <String, dynamic>{
        'purpose': 'other',
        'accountId': '22222222-2222-4222-8222-222222222222',
        'username': 'Bob',
        'oldIdentityHash': 'c' * 64,
        'newIdentityKey': base64Encode(next.publicKey),
        'fromEpoch': 1,
        'toEpoch': 2,
        'issuedAt': 899,
        'transferNonce': 'c' * 64,
      }.entries) {
        expect(
          verify({...p, entry.key: entry.value}, signature, old),
          isNull,
          reason: entry.key,
        );
      }
    }),
  );
  test(
    'another old key does not establish continuity',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh);
      expect(verify(p, sign(p, old, fresh), next), isNull);
    }),
  );
  test(
    'changed account or username rejects an otherwise valid signature',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), signature = sign(p, old, fresh);
      expect(verify(p, signature, old, owner: 'Bob'), isNull);
      expect(
        verify(
          p,
          signature,
          old,
          account: '22222222-2222-4222-8222-222222222222',
        ),
        isNull,
      );
    }),
  );
  test(
    'replay cannot advance a contact already at a newer epoch',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), signature = sign(p, old, fresh);
      expect(verify(p, signature, old, epoch: 1), isNull);
      expect(verify(p, signature, old, epoch: 2), isNull);
    }),
  );
  test(
    'future timestamp and invalid local clock fail closed',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), signature = sign(p, old, fresh);
      expect(verify(p, signature, old, now: 899), isNull);
      expect(verify(p, signature, old, now: -1), isNull);
    }),
  );
  test(
    'signer requires explicit confirmation and exact active context',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh);
      expect(() => sign(p, old, fresh, confirmed: false), throwsStateError);
      expect(() => sign(p, old, fresh, epoch: 1), throwsStateError);
      expect(() => sign(p, old, next), throwsStateError);
      expect(() => sign(p, old, fresh, nonce: 'c'), throwsStateError);
      expect(
        () => sign(
          {...p, 'oldIdentityHash': sha256.convert(next.publicKey).toString()},
          old,
          fresh,
        ),
        throwsStateError,
      );
    }),
  );
  test(
    'malformed and noncanonical signatures fail closed',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), signature = sign(p, old, fresh);
      for (final sig in [
        'bad',
        signature + '\n',
        base64Encode(List.filled(64, 0)),
      ]) {
        expect(verify(p, sig, old), isNull);
      }
    }),
  );
  test(
    'field order is canonical and unknown fields are rejected',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh),
          reordered = Map<String, dynamic>.fromEntries(
            p.entries.toList().reversed,
          );
      expect(deviceKeyTransitionBytes(p), deviceKeyTransitionBytes(reordered));
      expect(verify({...p, 'extra': true}, sign(p, old, fresh), old), isNull);
    }),
  );
  test(
    'invalid epochs times public encodings and nonce are rejected',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh);
      for (final entry in <String, dynamic>{
        'fromEpoch': -1,
        'toEpoch': 3,
        'issuedAt': 1.5,
        'newIdentityKey': 'bad',
        'transferNonce': 'bad',
      }.entries) {
        expect(
          () => deviceKeyTransitionBytes({...p, entry.key: entry.value}),
          throwsFormatException,
        );
      }
      expect(
        () => deviceKeyTransitionBytes({
          ...p,
          'fromEpoch': 9007199254740991,
          'toEpoch': 9007199254740992,
        }),
        throwsFormatException,
      );
    }),
  );
  test(
    'no-op key transition is rejected',
    () => fixture((old, fresh, next) {
      expect(
        () => deviceKeyTransitionBytes(payload(old, old)),
        throwsFormatException,
      );
    }),
  );
  test(
    'short-lived approval signature cannot be reused as a durable certificate',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh),
          approval = {
            'purpose': 'fenyvo-device-transfer-v1',
            'accountId': id,
            'username': 'Alice',
            'oldIdentityHash': p['oldIdentityHash'],
            'newIdentityKey': p['newIdentityKey'],
            'candidateHash': sha256.convert(fresh.publicKey).toString(),
            'nonce': 'b' * 64,
            'issuedAt': 900,
            'expiresAt': 120900,
          };
      final signature = base64Encode(
        old.sign(message: deviceTransferApprovalBytes(approval)),
      );
      expect(verify(p, signature, old), isNull);
    }),
  );
  test(
    'verified result payload and public-key access are immutable',
    () => fixture((old, fresh, next) {
      final p = payload(old, fresh), r = verify(p, sign(p, old, fresh), old)!;
      p['username'] = 'Bob';
      r.newIdentityKey[0] = 0;
      expect(r.payload['username'], 'Alice');
      expect(r.newIdentityKey.first, 5);
      expect(() => r.payload['username'] = 'Bob', throwsUnsupportedError);
    }),
  );
  test(
    'offline contact verifies two consecutive transitions',
    () => fixture((old, fresh, next) {
      final first = payload(old, fresh),
          second = payload(fresh, next, epoch: 1, issued: 1100, nonce: 'c');
      final chain = verifyDeviceKeyTransitionChain(
        certificates: [
          {'payload': first, 'signature': sign(first, old, fresh)},
          {
            'payload': second,
            'signature': sign(
              second,
              fresh,
              next,
              epoch: 1,
              now: 1200,
              nonce: 'c',
            ),
          },
        ],
        trustedOldIdentityKey: old.publicKey,
        accountId: id,
        username: 'Alice',
        storedEpoch: 0,
        nowMs: 1000000000000,
      )!;
      expect(chain.finalEpoch, 2);
      expect(chain.finalIdentityKey, next.publicKey);
      expect(() => chain.transitions.clear(), throwsUnsupportedError);
    }),
  );
  test(
    'missing reversed duplicated and substituted chain links are rejected',
    () => fixture((old, fresh, next) {
      final first = payload(old, fresh),
          second = payload(fresh, next, epoch: 1, issued: 1100, nonce: 'c');
      final a = {'payload': first, 'signature': sign(first, old, fresh)},
          b = {
            'payload': second,
            'signature': sign(
              second,
              fresh,
              next,
              epoch: 1,
              now: 1200,
              nonce: 'c',
            ),
          };
      for (final chain in <List<Map<String, dynamic>>>[
        [b],
        [b, a],
        [a, a],
        [
          a,
          {'payload': second, 'signature': a['signature']},
        ],
      ]) {
        expect(
          verifyDeviceKeyTransitionChain(
            certificates: chain,
            trustedOldIdentityKey: old.publicKey,
            accountId: id,
            username: 'Alice',
            storedEpoch: 0,
            nowMs: 2000,
          ),
          isNull,
        );
      }
    }),
  );
  test(
    'empty and oversized chains have bounded rejection',
    () => fixture((old, fresh, next) {
      for (final chain in <List<Map<String, dynamic>>>[
        [],
        List.filled(33, <String, dynamic>{}),
      ]) {
        expect(
          verifyDeviceKeyTransitionChain(
            certificates: chain,
            trustedOldIdentityKey: old.publicKey,
            accountId: id,
            username: 'Alice',
            storedEpoch: 0,
            nowMs: 2000,
          ),
          isNull,
        );
      }
    }),
  );
}
