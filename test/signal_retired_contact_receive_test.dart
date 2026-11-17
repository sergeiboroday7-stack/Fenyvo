import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';
import 'package:spartan_chat_final/services/crypto/signal_e2ee_service.dart';
import 'package:spartan_chat_final/services/crypto/device_key_transition.dart';

import 'signal_contact_continuity_test.dart' as support;

const id = '11111111-1111-4111-8111-111111111111';
String key(String kind) =>
    'spartan_signal_v2.' +
    base64Url.encode(utf8.encode('bob-test')) +
    '.' +
    kind +
    '.' +
    base64Url.encode(utf8.encode('alice-test')) +
    '.1';
Future<void> fixture(
  Future<void> Function(
    SignalSecureStore,
    ProtocolAddress,
    IdentityKeyPair,
    CiphertextMessage,
    CiphertextMessage,
    CiphertextMessage,
  )
  body,
) async {
  final service = SignalE2eeService.instance;
  await service.initializeForUser('bob-test');
  final alice = SignalSecureStore('alice-test');
  final bob = SignalSecureStore('bob-test');
  final aliceIdentity = await alice.ensureIdentity();
  final bobIdentity = await bob.ensureIdentity();

  const preKeyId = 1;
  final preKeyPrivate = PrivateKey.generate();
  final preKey = PreKeyRecord(
    id: preKeyId,
    publicKey: preKeyPrivate.getPublicKey(),
    privateKey: preKeyPrivate,
  );
  await bob.storePreKey(preKeyId, preKey);

  const signedPreKeyId = 1;
  final signedPrivate = PrivateKey.generate();
  final signedPublic = signedPrivate.getPublicKey();
  final signedSignature = bobIdentity.sign(message: signedPublic.serialize());
  final signedPreKey = SignedPreKeyRecord(
    id: signedPreKeyId,
    timestamp: BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch),
    publicKey: signedPublic,
    privateKey: signedPrivate,
    signature: signedSignature,
  );
  await bob.storeSignedPreKey(signedPreKeyId, signedPreKey);

  const kyberPreKeyId = 1;
  final kyberPair = KyberKeyPair.generate();
  final kyberPublic = kyberPair.getPublicKey();
  final kyberSignature = bobIdentity.sign(message: kyberPublic.serialize());
  final kyberPreKey = KyberPreKeyRecord.create(
    id: kyberPreKeyId,
    timestamp: BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch),
    keyPair: kyberPair,
    signature: kyberSignature,
  );
  await bob.storeKyberPreKey(kyberPreKeyId, kyberPreKey);

  final aliceAddress = ProtocolAddress(name: 'alice-test', deviceId: 1);
  final bobAddress = ProtocolAddress(name: 'bob-test', deviceId: 1);
  final bundle = PreKeyBundle(
    registrationId: await bob.ensureRegistrationId(),
    deviceId: 1,
    preKeyId: preKeyId,
    preKeyPublic: Uint8List.fromList(preKey.publicKey()),
    signedPreKeyId: signedPreKeyId,
    signedPreKeyPublic: signedPreKey.publicKey(),
    signedPreKeySignature: signedPreKey.signature(),
    identityKey: bobIdentity.publicKey,
    kyberPreKeyId: kyberPreKeyId,
    kyberPreKeyPublic: kyberPublic.serialize(),
    kyberPreKeySignature: kyberSignature,
  );
  await SessionBuilder(
    localAddress: aliceAddress,
    sessionStore: alice,
    identityKeyStore: alice,
  ).processPreKeyBundle(bobAddress, bundle);

  final aliceCipher = SessionCipher(
    localAddress: aliceAddress,
    sessionStore: alice,
    identityKeyStore: alice,
    preKeyStore: alice,
    signedPreKeyStore: alice,
    kyberPreKeyStore: alice,
  );
  final bobCipher = SessionCipher(
    localAddress: bobAddress,
    sessionStore: bob,
    identityKeyStore: bob,
    preKeyStore: bob,
    signedPreKeyStore: bob,
    kyberPreKeyStore: bob,
  );

  try {
    final first = await aliceCipher.encrypt(
      bobAddress,
      Uint8List.fromList(utf8.encode(jsonEncode({'text': 'first'}))),
    );
    await bobCipher.decrypt(aliceAddress, first);
    final reply = await bobCipher.encrypt(
      aliceAddress,
      Uint8List.fromList(utf8.encode('ack')),
    );
    await aliceCipher.decrypt(bobAddress, reply);
    final late1 = await aliceCipher.encrypt(
      bobAddress,
      Uint8List.fromList(utf8.encode(jsonEncode({'text': 'late-one'}))),
    );
    final late2 = await aliceCipher.encrypt(
      bobAddress,
      Uint8List.fromList(utf8.encode(jsonEncode({'text': 'late-two'}))),
    );
    expect(late1.type.value, 2);
    await body(bob, aliceAddress, aliceIdentity, first, late1, late2);
  } finally {
    aliceIdentity.dispose();
    bobIdentity.dispose();
  }
}

Future<void> transition(IdentityKeyPair old, {bool badBundle = false}) async {
  final fresh = IdentityKeyPair.generate();
  try {
    final now = DateTime.now().millisecondsSinceEpoch,
        payload = <String, dynamic>{
          'purpose': 'fenyvo-device-key-transition-v1',
          'accountId': id,
          'username': 'alice-test',
          'oldIdentityHash': sha256.convert(old.publicKey).toString(),
          'newIdentityKey': base64Encode(fresh.publicKey),
          'fromEpoch': 0,
          'toEpoch': 1,
          'issuedAt': now - 1,
          'transferNonce': 'b' * 64,
        };
    final signature = signDeviceKeyTransition(
      payload: payload,
      identity: old,
      accountId: id,
      username: 'alice-test',
      fromEpoch: 0,
      newIdentityKey: fresh.publicKey,
      transferNonce: 'b' * 64,
      nowMs: now,
      userConfirmed: true,
    );
    final bundle = support.bundle(fresh);
    if (badBundle)
      (bundle['signedPreKey'] as Map)['signature'] = base64Encode(
        List<int>.filled(64, 0),
      );
    await SignalE2eeService.instance.acceptContinuityVerifiedRemoteBundle(
      'alice-test',
      bundle,
      expectedAccountId: id,
      certificates: [
        {'payload': payload, 'signature': signature},
      ],
      isSessionCurrent: () => true,
    );
  } finally {
    fresh.dispose();
  }
}

Map<String, dynamic> envelope(CiphertextMessage message) => {
  'cipherType': message.type.value,
  'ciphertext': base64Encode(message.ciphertext),
};
Future<Map<String, String>> snapshot() =>
    const FlutterSecureStorage().readAll();
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SignalE2eeService.instance.prepareDeviceTransferCrypto();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('out-of-order old ciphertext decrypts without replacing active trust or ratchet', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      final active = await store.getIdentity(address),
          session = await store.loadSession(address);
      final activeBytes = session!.serialize();
      try {
        expect(
          await SignalE2eeService.instance.decryptRetiredContactMessage(
            'alice-test',
            envelope(two),
            isSessionCurrent: () => true,
          ),
          {'text': 'late-two'},
        );
        expect(
          await SignalE2eeService.instance.decryptRetiredContactMessage(
            'alice-test',
            envelope(one),
            isSessionCurrent: () => true,
          ),
          {'text': 'late-one'},
        );
        final identity = await store.getIdentity(address);
        try {
          expect(identity!.serialize(), active!.serialize());
        } finally {
          identity?.dispose();
        }
        expect((await store.loadSession(address))!.serialize(), activeBytes);
        expect((await store.readPeerContinuity(address))!['epoch'], 1);
      } finally {
        active?.dispose();
      }
    });
  });
  test('archive ratchet replay is rejected and unchanged', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      await SignalE2eeService.instance.decryptRetiredContactMessage(
        'alice-test',
        envelope(one),
        isSessionCurrent: () => true,
      );
      final before = await snapshot();
      await expectLater(
        SignalE2eeService.instance.decryptRetiredContactMessage(
          'alice-test',
          envelope(one),
          isSessionCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  });
  test('tampering does not advance archive or active state', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      final before = await snapshot(),
          bytes = Uint8List.fromList(one.ciphertext);
      bytes[bytes.length - 1] ^= 1;
      await expectLater(
        SignalE2eeService.instance.decryptRetiredContactMessage('alice-test', {
          'cipherType': 2,
          'ciphertext': base64Encode(bytes),
        }, isSessionCurrent: () => true),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  });
  test('fresh store resumes archived receive state after restart', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      final reloaded = SignalSecureStore('bob-test');
      expect(
        jsonDecode(
          utf8.decode(
            await reloaded.decryptRetiredPeerMessage(
              address,
              one,
              isCurrent: () => true,
            ),
          ),
        ),
        {'text': 'late-one'},
      );
    });
  });
  test('cancelled session cannot receive retired traffic', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      final before = await snapshot();
      await expectLater(
        SignalE2eeService.instance.decryptRetiredContactMessage(
          'alice-test',
          envelope(one),
          isSessionCurrent: () => false,
        ),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  });
  test(
    'old pre-key handshake is never accepted through retired store',
    () async {
      await fixture((store, address, old, first, one, two) async {
        await transition(old);
        final before = await snapshot();
        await expectLater(
          SignalE2eeService.instance.decryptRetiredContactMessage(
            'alice-test',
            envelope(first),
            isSessionCurrent: () => true,
          ),
          throwsStateError,
        );
        expect(await snapshot(), before);
      });
    },
  );
  test('failed verified bundle rolls back archive and trusted state with journal v3', () async {
    await fixture((store, address, old, first, one, two) async {
      final before = await snapshot();
      await expectLater(
        transition(old, badBundle: true),
        throwsA(isA<Object>()),
      );
      expect(await snapshot(), before);
    });
  });
  test(
    'interrupted v3 transaction restores prior archive before removing journal',
    () async {
      await fixture((store, address, old, first, one, two) async {
        final before = await snapshot(),
            session = await store.loadSession(address),
            identity = await store.getIdentity(address);
        try {
          await store.beginVerifiedPeerRecovery(
            address,
            session,
            identity,
            preserveRetiredSession: true,
          );
          await store.preserveRetiredPeerSession(
            address,
            session!,
            identity!,
            accountId: id,
            fromEpoch: 0,
            toEpoch: 1,
          );
          await store.deleteSession(address);
          await store.deleteRemoteIdentity(address);
          await SignalSecureStore('bob-test')
              .restorePendingVerifiedPeerRecovery();
          expect(await snapshot(), before);
        } finally {
          identity?.dispose();
        }
      });
    },
  );
  test('expired snapshot is retained but cannot receive', () async {
    await fixture((store, address, old, first, one, two) async {
      await transition(old);
      final storage = const FlutterSecureStorage(),
          raw = await storage.read(key: key('retired_sessions'));
      final data = jsonDecode(raw!) as Map;
      (data['entries'] as List).first['retiredAt'] = 0;
      await storage.write(
        key: key('retired_sessions'),
        value: jsonEncode(data),
      );
      final before = await snapshot();
      await expectLater(
        SignalE2eeService.instance.decryptRetiredContactMessage(
          'alice-test',
          envelope(one),
          isSessionCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  });
  test(
    'capacity refuses another snapshot without evicting existing sessions',
    () async {
      await fixture((store, address, old, first, one, two) async {
        final session = await store.loadSession(address),
            identity = await store.getIdentity(address);
        try {
          for (var i = 0; i < 4; i++) {
            await store.preserveRetiredPeerSession(
              address,
              session!,
              identity!,
              accountId: id,
              fromEpoch: i,
              toEpoch: i + 1,
            );
          }
          final before = await snapshot();
          await expectLater(
            store.preserveRetiredPeerSession(
              address,
              session!,
              identity!,
              accountId: id,
              fromEpoch: 4,
              toEpoch: 5,
            ),
            throwsStateError,
          );
          expect(await snapshot(), before);
        } finally {
          identity?.dispose();
        }
      });
    },
  );
  test(
    'corrupt snapshot blocks transition without deleting current keys',
    () async {
      await fixture((store, address, old, first, one, two) async {
        await const FlutterSecureStorage().write(
          key: key('retired_sessions'),
          value: 'corrupt',
        );
        final before = await snapshot();
        await expectLater(transition(old), throwsA(isA<Object>()));
        expect(await snapshot(), before);
      });
    },
  );
}
