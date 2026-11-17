import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:spartan_chat_final/services/crypto/device_transfer_candidate_store.dart';
import 'package:spartan_chat_final/services/crypto/device_key_transition.dart';
import 'package:spartan_chat_final/services/crypto/old_device_pin.dart';
import 'package:spartan_chat_final/services/crypto/signal_e2ee_service.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';

const accountId = '11111111-1111-4111-8111-111111111111', owner = 'Alice';
final journal =
    'fenyvo_transfer_v2.' + base64Url.encode(utf8.encode(owner)) + '.candidate';
final activeKey =
    'spartan_signal_v2.' +
    base64Url.encode(utf8.encode(owner)) +
    '.identity.pair';
bool current() => true;

class Fixture {
  final old = IdentityKeyPair.generate();
  late final pin = OldDevicePin.create(
    accountId: accountId,
    username: owner,
    publicKey: old.publicKey,
  );
  final store = DeviceTransferCandidateStore(owner);
  Future<PendingTransferCandidate> stage() =>
      store.createOrResume(pin, isOperationCurrent: current);
  VerifiedDeviceKeyTransition proof(
    PendingTransferCandidate candidate, {
    String nonce = 'b',
    String? newKey,
    String account = accountId,
  }) {
    final p = {
      'purpose': 'fenyvo-device-key-transition-v1',
      'accountId': account,
      'username': owner,
      'oldIdentityHash': sha256.convert(old.publicKey).toString(),
      'newIdentityKey': newKey ?? candidate.identityKey,
      'fromEpoch': 0,
      'toEpoch': 1,
      'issuedAt': 1000,
      'transferNonce': nonce * 64,
    };
    final signature = signDeviceKeyTransition(
      payload: p,
      identity: old,
      accountId: account,
      username: owner,
      fromEpoch: 0,
      newIdentityKey: base64Decode(p['newIdentityKey'] as String),
      transferNonce: nonce * 64,
      nowMs: 1001,
      userConfirmed: true,
    );
    return verifyDeviceKeyTransition(
      payload: p,
      signature: signature,
      trustedOldIdentityKey: old.publicKey,
      accountId: account,
      username: owner,
      storedEpoch: 0,
      nowMs: 1001,
    )!;
  }

  Future<PendingTransferCandidate> verified() async {
    final c = await stage();
    return store.recordVerifiedCertificate(
      proof(c),
      expectedTransferNonce: 'b' * 64,
      isOperationCurrent: current,
    );
  }

  Future<void> committed() async {
    await verified();
    await store.observeCommit(
      {
        'accountId': accountId,
        'epoch': 1,
        'transferNonce': 'b' * 64,
        'committed': true,
      },
      expectedTransferNonce: 'b' * 64,
      fromStatus: false,
      isOperationCurrent: current,
    );
  }

  Future<Map<String, String>> snapshot() =>
      const FlutterSecureStorage().readAll();
}

Future<void> fixture(Future<void> Function(Fixture) body) async {
  final f = Fixture();
  try {
    await body(f);
  } finally {
    f.old.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SignalE2eeService.instance.prepareDeviceTransferCrypto();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('staged candidate survives new instances without creating an active identity', () async {
    await fixture((f) async {
      final c = await f.stage(),
          restored = await DeviceTransferCandidateStore(owner).readPublic();
      expect(restored!.identityKey, c.identityKey);
      expect(restored.phase, 'staged');
      expect(await const FlutterSecureStorage().read(key: activeKey), isNull);
    });
  });
  test(
    'public view never exposes private pair and is deeply immutable',
    () async {
      await fixture((f) async {
        final c = await f.verified();
        expect(c.publicData.containsKey('privateIdentityPair'), isFalse);
        expect(() => c.publicData['phase'] = 'other', throwsUnsupportedError);
        expect(
          () => c.publicData['certificate']['payload']['username'] = 'Bob',
          throwsUnsupportedError,
        );
      });
    },
  );
  test('existing profile key prevents staging and is never replaced', () async {
    await fixture((f) async {
      final existing = await SignalSecureStore(owner).ensureIdentity(),
          before = await f.snapshot();
      try {
        await expectLater(f.stage(), throwsStateError);
        expect(await f.snapshot(), before);
        expect(await const FlutterSecureStorage().read(key: journal), isNull);
      } finally {
        existing.dispose();
      }
    });
  });
  test(
    'another account or old trust anchor cannot overwrite a sealed candidate',
    () async {
      await fixture((f) async {
        await f.stage();
        final before = await f.snapshot(), other = IdentityKeyPair.generate();
        try {
          await expectLater(
            f.store.createOrResume(
              OldDevicePin.create(
                accountId: accountId,
                username: owner,
                publicKey: other.publicKey,
              ),
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
          await expectLater(
            f.store.createOrResume(
              OldDevicePin.create(
                accountId: '22222222-2222-4222-8222-222222222222',
                username: owner,
                publicKey: f.old.publicKey,
              ),
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
          expect(await f.snapshot(), before);
        } finally {
          other.dispose();
        }
      });
    },
  );
  test('no proof or no commit receipt cannot install a local key', () async {
    await fixture((f) async {
      await f.stage();
      await expectLater(
        f.store.installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: current,
        ),
        throwsStateError,
      );
      await f.verified();
      await expectLater(
        f.store.installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: current,
        ),
        throwsStateError,
      );
      expect(await const FlutterSecureStorage().read(key: activeKey), isNull);
    });
  });
  test(
    'verified proof must match sealed candidate account key and nonce',
    () async {
      await fixture((f) async {
        final c = await f.stage(),
            other = IdentityKeyPair.generate(),
            before = await f.snapshot();
        try {
          await expectLater(
            f.store.recordVerifiedCertificate(
              f.proof(c, newKey: base64Encode(other.publicKey)),
              expectedTransferNonce: 'b' * 64,
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
          await expectLater(
            f.store.recordVerifiedCertificate(
              f.proof(c, account: '22222222-2222-4222-8222-222222222222'),
              expectedTransferNonce: 'b' * 64,
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
          await expectLater(
            f.store.recordVerifiedCertificate(
              f.proof(c),
              expectedTransferNonce: 'c' * 64,
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
          expect(await f.snapshot(), before);
        } finally {
          other.dispose();
        }
      });
    },
  );
  test(
    'stale or mismatched server status cannot confirm installation',
    () async {
      await fixture((f) async {
        await f.verified();
        final before = await f.snapshot();
        for (final receipt in <Map<String, dynamic>>[
          {
            'accountId': accountId,
            'epoch': 1,
            'committed': true,
            'isCurrent': false,
          },
          {
            'accountId': accountId,
            'epoch': 2,
            'committed': true,
            'isCurrent': true,
          },
          {
            'accountId': accountId,
            'epoch': 1,
            'committed': false,
            'isCurrent': true,
          },
        ]) {
          await expectLater(
            f.store.observeCommit(
              receipt,
              expectedTransferNonce: 'b' * 64,
              fromStatus: true,
              isOperationCurrent: current,
            ),
            throwsStateError,
          );
        }
        expect(await f.snapshot(), before);
      });
    },
  );
  test('committed candidate installs exactly once and is resumable', () async {
    await fixture((f) async {
      await f.committed();
      final view = (await f.store.readPublic())!;
      final reloaded = DeviceTransferCandidateStore(owner);
      await reloaded.installForActivation(
        expectedTransferNonce: 'b' * 64,
        isOperationCurrent: current,
      );
      final before = await const FlutterSecureStorage().read(key: activeKey);
      await reloaded.installForActivation(
        expectedTransferNonce: 'b' * 64,
        isOperationCurrent: current,
      );
      expect(await const FlutterSecureStorage().read(key: activeKey), before);
      final identity = await SignalSecureStore(owner).ensureIdentity();
      try {
        expect(base64Encode(identity.publicKey), view.identityKey);
      } finally {
        identity.dispose();
      }
      expect((await reloaded.readPublic())!.phase, 'installed');
    });
  });
  test(
    'installed candidate journal can restore a missing active slot',
    () async {
      await fixture((f) async {
        await f.committed();
        await f.store.installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: current,
        );
        final key = (await f.store.readPublic())!.identityKey;
        await const FlutterSecureStorage().delete(key: activeKey);
        await DeviceTransferCandidateStore(owner).installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: current,
        );
        final identity = await SignalSecureStore(owner)
            .readExistingIdentityForTransfer();
        try {
          expect(base64Encode(identity.publicKey), key);
        } finally {
          identity.dispose();
        }
      });
    },
  );
  test('a competing ordinary identity creation cannot be overwritten by installation', () async {
    await fixture((f) async {
      await f.committed();
      final ordinary = await SignalSecureStore(owner).ensureIdentity(),
          before = await f.snapshot();
      try {
        await expectLater(
          f.store.installForActivation(
            expectedTransferNonce: 'b' * 64,
            isOperationCurrent: current,
          ),
          throwsStateError,
        );
        expect(await f.snapshot(), before);
      } finally {
        ordinary.dispose();
      }
    });
  });
  test(
    'concurrent ensure and fresh install share the same identity lock',
    () async {
      final store = SignalSecureStore(owner),
          candidate = IdentityKeyPair.generate();
      final results = await Future.wait<dynamic>([
        store.ensureIdentity(),
        store
            .installFreshTransferredIdentity(candidate)
            .then<String>((_) => 'installed')
            .catchError((Object _) => 'blocked'),
      ]);
      final ensured = results[0] as IdentityKeyPair,
          actual = await store.readExistingIdentityForTransfer();
      try {
        expect(actual.publicKey, ensured.publicKey);
      } finally {
        ensured.dispose();
        actual.dispose();
        candidate.dispose();
      }
    },
  );
  test('definitive uncommitted status resets only proof and retains the same private candidate', () async {
    await fixture((f) async {
      await f.verified();
      final key = (await f.store.readPublic())!.identityKey;
      await f.store.resetAfterUncommittedStatus(
        {'committed': false},
        expectedTransferNonce: 'b' * 64,
        isOperationCurrent: current,
      );
      final c = await f.stage();
      expect(c.identityKey, key);
      expect(c.phase, 'staged');
      expect(c.transferNonce, isNull);
    });
  });
  test(
    'committed receipt cannot be discarded as an uncommitted attempt',
    () async {
      await fixture((f) async {
        await f.committed();
        final before = await f.snapshot();
        await expectLater(
          f.store.resetAfterUncommittedStatus(
            {'committed': false},
            expectedTransferNonce: 'b' * 64,
            isOperationCurrent: current,
          ),
          throwsStateError,
        );
        expect(await f.snapshot(), before);
      });
    },
  );
  test(
    'corrupt candidate is retained and never silently regenerated',
    () async {
      await fixture((f) async {
        await f.stage();
        final raw = await const FlutterSecureStorage().read(key: journal),
            data = jsonDecode(raw!) as Map;
        data['privateIdentityPair'] = 'invalid';
        await const FlutterSecureStorage().write(
          key: journal,
          value: jsonEncode(data),
        );
        final before = await f.snapshot();
        await expectLater(f.store.readPublic(), throwsStateError);
        await expectLater(f.stage(), throwsStateError);
        expect(await f.snapshot(), before);
      });
    },
  );
  test('stale UI operation cannot stage or install a candidate', () async {
    await fixture((f) async {
      await expectLater(
        f.store.createOrResume(f.pin, isOperationCurrent: () => false),
        throwsStateError,
      );
      expect(await f.snapshot(), isEmpty);
      await f.committed();
      final before = await f.snapshot();
      await expectLater(
        f.store.installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: () => false,
        ),
        throwsStateError,
      );
      expect(await f.snapshot(), before);
    });
  });
  test(
    'restart completes a key write interrupted before the installed marker',
    () async {
      await fixture((f) async {
        await f.committed();
        final raw = await const FlutterSecureStorage().read(key: journal),
            record = jsonDecode(raw!) as Map;
        final bytes = base64Decode(record['privateIdentityPair'] as String);
        final identity = IdentityKeyPair.deserialize(bytes: bytes);
        bytes.fillRange(0, bytes.length, 0);
        try {
          await SignalSecureStore(owner)
              .installFreshTransferredIdentity(identity);
        } finally {
          identity.dispose();
        }
        expect((await f.store.readPublic())!.phase, 'committed');
        final before = await const FlutterSecureStorage().read(key: activeKey);
        await DeviceTransferCandidateStore(owner).installForActivation(
          expectedTransferNonce: 'b' * 64,
          isOperationCurrent: current,
        );
        expect(await const FlutterSecureStorage().read(key: activeKey), before);
        expect((await f.store.readPublic())!.phase, 'installed');
      });
    },
  );
  test(
    'owner scopes cannot expose another pending private candidate',
    () async {
      await fixture((f) async {
        await f.stage();
        expect(await DeviceTransferCandidateStore('Bob').readPublic(), isNull);
      });
    },
  );
}
