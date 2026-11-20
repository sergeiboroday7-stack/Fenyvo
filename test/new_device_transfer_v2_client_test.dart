import 'package:fenyvo/services/device_transfer_diagnostics.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/new_device_transfer_v2_client.dart';
import 'package:fenyvo/services/crypto/old_device_pin.dart';
import 'package:fenyvo/services/crypto/device_transfer_approval.dart';
import 'package:fenyvo/services/crypto/device_key_transition.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';
import 'package:fenyvo/services/crypto/signal_secure_store.dart';

const id = '11111111-1111-4111-8111-111111111111';
int seq = 0;

class Wire implements TransferV2Wire {
  Wire(this.old, this.owner);
  final IdentityKeyPair old;
  final String owner;
  final messages = StreamController<Map<String, dynamic>>();
  late final iterator = StreamIterator<Map<String, dynamic>>(messages.stream);
  final sent = <String>[];
  bool badProof = false,
      badChallenge = false,
      dropCommit = false,
      published = true,
      wrongActivation = false,
      uncommitted = false,
      stale = false;
  String? candidate;
  Object? openFailure;
  int openCalls = 0;
  void frame(String type, Map<String, dynamic> data) =>
      messages.add({'type': type, 'data': data});
  @override
  Future<void> open(Uri server) async {
    openCalls++;
    if (openFailure != null) throw openFailure!;
  }
  @override
  void send(String type, Map<String, dynamic> data) {
    sent.add(type == 'login' ? data['mode'] as String : type);
    if (type == 'login') {
      candidate = data['newIdentityKey'] as String;
      if (data['mode'] == 'device_transfer_prepare_v2') {
        final now = DateTime.now().millisecondsSinceEpoch;
        final request = <String, dynamic>{
          'purpose': 'fenyvo-device-transfer-v1',
          'accountId': id,
          'username': owner,
          'newIdentityKey': candidate,
          'candidateHash': sha256.convert(base64Decode(candidate!)).toString(),
          'nonce': 'b' * 64,
          'issuedAt': now - 1,
          'expiresAt': now + 120000,
        };
        final approval = {
          ...request,
          'oldIdentityHash': sha256.convert(old.publicKey).toString(),
        };
        final cert = <String, dynamic>{
          'purpose': 'fenyvo-device-key-transition-v1',
          'accountId': id,
          'username': owner,
          'oldIdentityHash': approval['oldIdentityHash'],
          'newIdentityKey': candidate,
          'fromEpoch': 0,
          'toEpoch': 1,
          'issuedAt': now - 1,
          'transferNonce': 'b' * 64,
        };
        final sig = signDeviceTransferApproval(
          payload: approval,
          identity: old,
          accountId: id,
          username: owner,
          newIdentityKey: base64Decode(candidate!),
          nonce: 'b' * 64,
          nowMs: now,
        );
        final csig = signDeviceKeyTransition(
          payload: cert,
          identity: old,
          accountId: id,
          username: owner,
          fromEpoch: 0,
          newIdentityKey: base64Decode(candidate!),
          transferNonce: 'b' * 64,
          nowMs: now,
          userConfirmed: true,
        );
        frame('connected', {});
        frame('device_transfer_pending_v2', {
          ...request,
          'fromEpoch': 0,
          if (badChallenge) 'nonce': 'c' * 64,
        });
        frame('device_transfer_proof_v2_unverified', {
          'approval': {
            'payload': approval,
            'signature': badProof ? base64Encode(List<int>.filled(64, 0)) : sig,
          },
          'certificate': {'payload': cert, 'signature': csig},
        });
      } else if (data['mode'] == 'device_transfer_status_v2') {
        frame(
          'device_transfer_status_v2',
          uncommitted
              ? {'committed': false}
              : {
                  'accountId': id,
                  'epoch': 1,
                  'committed': true,
                  'isCurrent': !stale,
                },
        );
      } else if (data['mode'] == 'device_transfer_activate_v2') {
        frame('login_success', {
          'username': owner,
          'accountId': id,
          'deviceTransferActivated': !wrongActivation,
          'deviceTransferEpoch': 1,
        });
      } else
        throw StateError('Ordinary login forbidden');
    } else if (type == 'device_transfer_commit_v2') {
      if (!dropCommit)
        frame('device_transfer_committed_v2', {
          'accountId': id,
          'epoch': 1,
          'committed': true,
          'transferNonce': data['transferNonce'],
        });
    } else if (type == 'e2ee_publish_bundle') {
      if (data['identityKey'] != candidate) throw StateError('Wrong bundle');
      frame('e2ee_bundle_published', {'ok': published});
    }
  }

  @override
  Future<Map<String, dynamic>> receive() async {
    if (!await iterator.moveNext()) throw StateError('Closed');
    return iterator.current;
  }

  @override
  Future<void> close() async {
    unawaited(messages.close());
    await iterator.cancel();
  }
}

Future<void> fixture(
  Future<void> Function(String, OldDevicePin, IdentityKeyPair) body,
) async {
  final owner = 'v2-new-' + (++seq).toString(),
      old = IdentityKeyPair.generate();
  try {
    await body(
      owner,
      OldDevicePin.create(
        accountId: id,
        username: owner,
        publicKey: old.publicKey,
      ),
      old,
    );
  } finally {
    old.dispose();
  }
}

NewDeviceTransferV2Client client(OldDevicePin pin, Wire wire, {Uri? server}) =>
    NewDeviceTransferV2Client(
      server: server ?? Uri.parse('ws://127.0.0.1/ws'),
      pin: pin,
      wire: wire,
      responseTimeout: const Duration(milliseconds: 100),
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SignalE2eeService.instance.prepareDeviceTransferCrypto();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'verified commit activation and bundle acknowledgement are all required',
    () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner), c = client(pin, wire);
        await c.run(password: 'synthetic-password');
        expect(c.phase, TransferV2Phase.ready);
        expect(wire.sent, [
          'device_transfer_prepare_v2',
          'device_transfer_commit_v2',
          'device_transfer_activate_v2',
          'e2ee_publish_bundle',
        ]);
        final active = await SignalSecureStore(owner)
            .readExistingIdentityForTransfer();
        try {
          expect(base64Encode(active.publicKey), c.candidate!.identityKey);
        } finally {
          active.dispose();
        }
        c.dispose();
      });
    },
  );
  for (final scenario in ['bad signature', 'wrong challenge']) {
    test(scenario + ' cannot commit or install', () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner);
        wire.badProof = scenario == 'bad signature';
        wire.badChallenge = scenario == 'wrong challenge';
        final c = client(pin, wire);
        await c.run(password: 'test');
        expect(c.phase, TransferV2Phase.interrupted);
        expect(wire.sent, isNot(contains('device_transfer_commit_v2')));
        expect(await SignalSecureStore(owner).hasLocalIdentity(), isFalse);
        expect((await c.store.readPublic())!.phase, 'staged');
        c.dispose();
      });
    });
  }
  test(
    'lost commit reply retains proof and resumes by status before activation',
    () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner)..dropCommit = true;
        final c = client(pin, wire);
        await c.run(password: 'test');
        expect(c.phase, TransferV2Phase.interrupted);
        final key = c.candidate!.identityKey;
        expect((await c.store.readPublic())!.phase, 'verified');
        c.dispose();
        final next = Wire(old, owner), resumed = client(pin, next);
        await resumed.run(password: 'test');
        expect(resumed.phase, TransferV2Phase.ready);
        expect(resumed.candidate!.identityKey, key);
        expect(next.sent.first, 'device_transfer_status_v2');
        expect(next.sent, isNot(contains('device_transfer_prepare_v2')));
        resumed.dispose();
      });
    },
  );
  test(
    'negative publication ACK never reports ready and preserves installed key',
    () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner)..published = false;
        final c = client(pin, wire);
        await c.run(password: 'test');
        expect(c.phase, TransferV2Phase.interrupted);
        expect((await c.store.readPublic())!.phase, 'installed');
        c.dispose();
        final next = client(pin, Wire(old, owner));
        await next.run(password: 'test');
        expect(next.phase, TransferV2Phase.ready);
        next.dispose();
      });
    },
  );
  test('early or mismatched login_success is insufficient', () async {
    await fixture((owner, pin, old) async {
      final wire = Wire(old, owner)..wrongActivation = true;
      final c = client(pin, wire);
      await c.run(password: 'test');
      expect(c.phase, TransferV2Phase.interrupted);
      expect(wire.sent, isNot(contains('e2ee_publish_bundle')));
      c.dispose();
    });
  });
  test(
    'stale directory status prevents activation and preserves sealed proof',
    () async {
      await fixture((owner, pin, old) async {
        final first = client(pin, Wire(old, owner)..dropCommit = true);
        await first.run(password: 'test');
        first.dispose();
        final wire = Wire(old, owner)..stale = true;
        final c = client(pin, wire);
        await c.run(password: 'test');
        expect(c.phase, TransferV2Phase.interrupted);
        expect(wire.sent, ['device_transfer_status_v2']);
        expect((await c.store.readPublic())!.phase, 'verified');
        c.dispose();
      });
    },
  );
  test(
    'definitive uncommitted status retains same candidate for a fresh prepare',
    () async {
      await fixture((owner, pin, old) async {
        final first = client(pin, Wire(old, owner)..dropCommit = true);
        await first.run(password: 'test');
        final key = first.candidate!.identityKey;
        first.dispose();
        final c = client(pin, Wire(old, owner)..uncommitted = true);
        await c.run(password: 'test');
        expect(c.phase, TransferV2Phase.interrupted);
        expect((await c.store.readPublic())!.phase, 'staged');
        expect(c.candidate!.identityKey, key);
        c.dispose();
        final next = client(pin, Wire(old, owner));
        await next.run(password: 'test');
        expect(next.phase, TransferV2Phase.ready);
        expect(next.candidate!.identityKey, key);
        next.dispose();
      });
    },
  );
  test(
    'ordinary existing identity is protected before any network request',
    () async {
      await fixture((owner, pin, old) async {
        final active = await SignalSecureStore(owner).ensureIdentity();
        final originalKey = base64Encode(active.publicKey);
        active.dispose();
        final wire = Wire(old, owner), c = client(pin, wire);
        await c.run(password: 'test');
        expect(wire.sent, isEmpty);
        expect(wire.openCalls, 0);
        expect(c.phase, TransferV2Phase.interrupted);
        expect(c.failure?.code, TransferFailureCode.existingProfile);
        expect(c.failure?.stage, TransferDiagnosticStage.localProfile);
        expect(c.candidate, isNull);
        final preserved = await SignalSecureStore(owner).readExistingIdentityForTransfer();
        try {
          expect(base64Encode(preserved.publicKey), originalKey);
        } finally {
          preserved.dispose();
        }
        c.dispose();
      });
    },
  );
  test('connection failure reports connection stage without sending credentials', () async {
    await fixture((owner, pin, old) async {
      final wire = Wire(old, owner)..openFailure = StateError('PRIVATE_CANARY');
      final c = client(pin, wire);
      await c.run(password: 'secret-password-canary');
      expect(c.phase, TransferV2Phase.interrupted);
      expect(c.failure?.code, TransferFailureCode.connection);
      expect(c.failure?.stage, TransferDiagnosticStage.connecting);
      expect(c.failure!.diagnosticCode, isNot(contains('CANARY')));
      expect(wire.sent, isEmpty);
      expect(await SignalSecureStore(owner).hasLocalIdentity(), isFalse);
      c.dispose();
    });
  });
  test(
    'insecure nonlocal endpoints cannot stage or send credentials',
    () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner),
            c = client(pin, wire, server: Uri.parse('ws://example.com/ws'));
        await c.run(password: 'test');
        expect(wire.sent, isEmpty);
        expect(await c.store.readPublic(), isNull);
        c.dispose();
      });
    },
  );
  test(
    'cancelled client cannot start or silently fall back to ordinary login',
    () async {
      await fixture((owner, pin, old) async {
        final wire = Wire(old, owner), c = client(pin, wire);
        await c.cancel();
        await expectLater(c.run(password: 'test'), throwsStateError);
        expect(wire.sent, isEmpty);
        c.dispose();
      });
    },
  );
}
