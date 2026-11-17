import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:spartan_chat_final/services/crypto/device_key_transition.dart';
import 'package:spartan_chat_final/services/crypto/signal_e2ee_service.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';

const accountId = '11111111-1111-4111-8111-111111111111';
int sequence = 0;
Map<String, dynamic> bundle(IdentityKeyPair identity) {
  final pre = PrivateKey.generate().getPublicKey().serialize(),
      signed = PrivateKey.generate().getPublicKey().serialize(),
      kyber = KyberKeyPair.generate().getPublicKey().serialize();
  return {
    'deviceId': 1,
    'registrationId': 42,
    'identityKey': base64Encode(identity.publicKey),
    'preKey': {'id': 1, 'publicKey': base64Encode(pre)},
    'signedPreKey': {
      'id': 1,
      'publicKey': base64Encode(signed),
      'signature': base64Encode(identity.sign(message: signed)),
    },
    'kyberPreKey': {
      'id': 1,
      'publicKey': base64Encode(kyber),
      'signature': base64Encode(identity.sign(message: kyber)),
    },
  };
}

Map<String, dynamic> certificate(
  IdentityKeyPair old,
  IdentityKeyPair fresh,
  int epoch,
) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final payload = {
    'purpose': 'fenyvo-device-key-transition-v1',
    'accountId': accountId,
    'username': 'Alice',
    'oldIdentityHash': sha256.convert(old.publicKey).toString(),
    'newIdentityKey': base64Encode(fresh.publicKey),
    'fromEpoch': epoch,
    'toEpoch': epoch + 1,
    'issuedAt': now - 1,
    'transferNonce': 'b' * 64,
  };
  return {
    'payload': payload,
    'signature': signDeviceKeyTransition(
      payload: payload,
      identity: old,
      accountId: accountId,
      username: 'Alice',
      fromEpoch: epoch,
      newIdentityKey: fresh.publicKey,
      transferNonce: 'b' * 64,
      nowMs: now,
      userConfirmed: true,
    ),
  };
}

class Fixture {
  final owner = 'continuity-owner-' + (++sequence).toString();
  final old = IdentityKeyPair.generate(),
      fresh = IdentityKeyPair.generate(),
      next = IdentityKeyPair.generate();
  final address = ProtocolAddress(name: 'Alice', deviceId: 1);
  final service = SignalE2eeService.instance;
  late final store = SignalSecureStore(owner);
  late final freshBundle = bundle(fresh);
  String key(String kind, String id) =>
      'spartan_signal_v2.' +
      base64Url.encode(utf8.encode(owner)) +
      '.' +
      kind +
      '.' +
      id;
  String get metadataKey =>
      key('peer_continuity', base64Url.encode(utf8.encode('Alice')) + '.1');
  String get journalKey => key('verified_recovery', 'pending');
  List<Map<String, dynamic>> chain() => [certificate(old, fresh, 0)];
  Future<void> initialize() async {
    await service.initializeForUser(owner);
    await service.processRemoteBundle('Alice', bundle(old));
  }

  Future<void> apply({
    List<Map<String, dynamic>>? certs,
    Map<String, dynamic>? data,
    bool Function()? current,
  }) => service.acceptContinuityVerifiedRemoteBundle(
    'Alice',
    data ?? freshBundle,
    expectedAccountId: accountId,
    certificates: certs ?? chain(),
    isSessionCurrent: current ?? () => true,
  );
  Future<Map<String, String>> snapshot() =>
      const FlutterSecureStorage().readAll();
  Future<void> expectOld() async {
    final identity = await store.getIdentity(address);
    try {
      expect(identity!.serialize(), old.publicKey);
    } finally {
      identity?.dispose();
    }
    expect(await store.containsSession(address), isTrue);
  }

  void dispose() {
    old.dispose();
    fresh.dispose();
    next.dispose();
  }
}

Future<void> fixture(Future<void> Function(Fixture) body) async {
  final f = Fixture();
  try {
    await f.initialize();
    await body(f);
  } finally {
    f.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final candidate = await SignalE2eeService.instance
        .createDeviceTransferCandidate();
    candidate.dispose();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'verified certificate installs the matching bundle session and epoch',
    () async {
      await fixture((f) async {
        await f.apply();
        final metadata = await f.store.readPeerContinuity(f.address);
        expect(metadata!['epoch'], 1);
        expect(metadata['accountId'], accountId);
        expect(
          metadata['identityHash'],
          sha256.convert(f.fresh.publicKey).toString(),
        );
        final identity = await f.store.getIdentity(f.address);
        try {
          expect(identity!.serialize(), f.fresh.publicKey);
        } finally {
          identity?.dispose();
        }
        expect(await f.store.containsSession(f.address), isTrue);
        expect(
          await const FlutterSecureStorage().read(key: f.journalKey),
          isNull,
        );
        expect(
          (await f.service.encrypt('Alice', {
            'text': 'continuity test',
          }))['e2eeProtocol'],
          'signal',
        );
      });
    },
  );
  test(
    'bad native pre-key signature restores old session identity and metadata',
    () async {
      await fixture((f) async {
        final before = await f.snapshot(),
            bad = Map<String, dynamic>.from(
              jsonDecode(jsonEncode(f.freshBundle)) as Map,
            );
        (bad['signedPreKey'] as Map)['signature'] = base64Encode(
          List.filled(64, 0),
        );
        await expectLater(f.apply(data: bad), throwsA(anything));
        await f.expectOld();
        expect(await f.snapshot(), before);
      });
    },
  );
  test('invalid certificate cannot modify existing trust', () async {
    await fixture((f) async {
      final before = await f.snapshot(), chain = f.chain();
      chain.first['signature'] = base64Encode(List.filled(64, 0));
      await expectLater(f.apply(certs: chain), throwsStateError);
      expect(await f.snapshot(), before);
    });
  });
  test('new bundle identity must match the certificate exactly', () async {
    await fixture((f) async {
      final before = await f.snapshot();
      await expectLater(f.apply(data: bundle(f.next)), throwsStateError);
      expect(await f.snapshot(), before);
    });
  });
  test(
    'old certificate replay does not roll back or replace newer session',
    () async {
      await fixture((f) async {
        final chain = f.chain();
        await f.apply(certs: chain);
        final before = await f.snapshot();
        await expectLater(f.apply(certs: chain), throwsStateError);
        expect(await f.snapshot(), before);
      });
    },
  );
  test('missing pinned old key cannot bootstrap automatic trust', () async {
    await fixture((f) async {
      await f.store.deleteRemoteIdentity(f.address);
      final before = await f.snapshot();
      await expectLater(f.apply(), throwsStateError);
      expect(await f.snapshot(), before);
    });
  });
  test('metadata for another account is rejected without changes', () async {
    await fixture((f) async {
      await const FlutterSecureStorage().write(
        key: f.metadataKey,
        value: jsonEncode({
          'version': 1,
          'accountId': '22222222-2222-4222-8222-222222222222',
          'epoch': 1,
          'identityHash': sha256.convert(f.old.publicKey).toString(),
        }),
      );
      final before = await f.snapshot();
      await expectLater(f.apply(), throwsStateError);
      expect(await f.snapshot(), before);
    });
  });
  test('corrupt continuity metadata fails closed', () async {
    await fixture((f) async {
      await const FlutterSecureStorage().write(
        key: f.metadataKey,
        value: 'invalid-json',
      );
      final before = await f.snapshot();
      await expectLater(f.apply(), throwsA(anything));
      expect(await f.snapshot(), before);
    });
  });
  test(
    'restart restores an interrupted v2 key session and epoch change',
    () async {
      await fixture((f) async {
        final oldIdentity = await f.store.getIdentity(f.address),
            oldSession = await f.store.loadSession(f.address);
        final oldBytes = oldSession!.serialize();
        await f.store.beginVerifiedPeerRecovery(
          f.address,
          oldSession,
          oldIdentity,
        );
        await f.store.deleteSession(f.address);
        await f.store.deleteRemoteIdentity(f.address);
        final fresh = PublicKey.deserialize(bytes: f.fresh.publicKey);
        await f.store.saveIdentity(f.address, fresh);
        fresh.dispose();
        final verified = verifyDeviceKeyTransitionChain(
          certificates: f.chain(),
          trustedOldIdentityKey: f.old.publicKey,
          accountId: accountId,
          username: 'Alice',
          storedEpoch: 0,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        await f.store.saveVerifiedPeerContinuity(f.address, verified);
        final reloaded = SignalSecureStore(f.owner);
        await reloaded.restorePendingVerifiedPeerRecovery();
        await f.expectOld();
        expect((await reloaded.loadSession(f.address))!.serialize(), oldBytes);
        expect(await reloaded.readPeerContinuity(f.address), isNull);
        expect(
          await const FlutterSecureStorage().read(key: f.journalKey),
          isNull,
        );
        oldIdentity?.dispose();
      });
    },
  );
  test(
    'committed continuity metadata persists in the correct account scope',
    () async {
      await fixture((f) async {
        await f.apply();
        final reloaded = SignalSecureStore(f.owner);
        await reloaded.restorePendingVerifiedPeerRecovery();
        expect((await reloaded.readPeerContinuity(f.address))!['epoch'], 1);
        expect(
          await SignalSecureStore('another-local-account')
              .readPeerContinuity(f.address),
          isNull,
        );
      });
    },
  );
  test('legacy v1 recovery journals remain readable', () async {
    await fixture((f) async {
      final identity = await f.store.getIdentity(f.address),
          session = await f.store.loadSession(f.address);
      await f.store.beginVerifiedPeerRecovery(f.address, session, identity);
      final raw = await const FlutterSecureStorage().read(key: f.journalKey),
          data = jsonDecode(raw!) as Map;
      data['version'] = 1;
      data.remove('continuity');
      await const FlutterSecureStorage().write(
        key: f.journalKey,
        value: jsonEncode(data),
      );
      await f.store.deleteSession(f.address);
      await f.store.deleteRemoteIdentity(f.address);
      await f.store.restorePendingVerifiedPeerRecovery();
      await f.expectOld();
      identity?.dispose();
    });
  });
  test(
    'invalid v2 journal is retained before any destructive restore',
    () async {
      await fixture((f) async {
        final identity = await f.store.getIdentity(f.address),
            session = await f.store.loadSession(f.address);
        await f.store.beginVerifiedPeerRecovery(f.address, session, identity);
        final raw = await const FlutterSecureStorage().read(key: f.journalKey),
            data = jsonDecode(raw!) as Map;
        data['continuity'] = 'bad';
        await const FlutterSecureStorage().write(
          key: f.journalKey,
          value: jsonEncode(data),
        );
        await expectLater(
          f.store.restorePendingVerifiedPeerRecovery(),
          throwsA(anything),
        );
        await f.expectOld();
        expect(
          await const FlutterSecureStorage().read(key: f.journalKey),
          isNotNull,
        );
        identity?.dispose();
      });
    },
  );
  test('inactive session cannot start a continuity update', () async {
    await fixture((f) async {
      final before = await f.snapshot();
      await expectLater(f.apply(current: () => false), throwsStateError);
      expect(await f.snapshot(), before);
    });
  });
  test(
    'offline contact applies two certificate links to the latest bundle',
    () async {
      await fixture((f) async {
        await f.apply(
          certs: [
            certificate(f.old, f.fresh, 0),
            certificate(f.fresh, f.next, 1),
          ],
          data: bundle(f.next),
        );
        expect((await f.store.readPeerContinuity(f.address))!['epoch'], 2);
        final identity = await f.store.getIdentity(f.address);
        try {
          expect(identity!.serialize(), f.next.publicKey);
        } finally {
          identity?.dispose();
        }
      });
    },
  );
  test(
    'mismatched metadata key hash cannot silently reset the replay counter',
    () async {
      await fixture((f) async {
        await const FlutterSecureStorage().write(
          key: f.metadataKey,
          value: jsonEncode({
            'version': 1,
            'accountId': accountId,
            'epoch': 1,
            'identityHash': sha256.convert(f.fresh.publicKey).toString(),
          }),
        );
        final before = await f.snapshot();
        await expectLater(f.apply(), throwsStateError);
        expect(await f.snapshot(), before);
      });
    },
  );
}
