import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/device_transfer_request.dart';
import 'package:spartan_chat_final/services/crypto/device_transfer_approval.dart';
import 'package:spartan_chat_final/services/crypto/device_key_transition.dart';
import 'package:spartan_chat_final/services/crypto/signal_e2ee_service.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';

const id = '11111111-1111-4111-8111-111111111111';
int sequence = 0;
Future<void> fixture(
  Future<void> Function(String, Map<String, dynamic>) body,
) async {
  final owner = 'old-device-' + (++sequence).toString(),
      service = SignalE2eeService.instance;
  await service.initializeForUser(owner);
  final fresh = await service.createDeviceTransferCandidate();
  final now = DateTime.now().millisecondsSinceEpoch;
  final data = {
    'purpose': 'fenyvo-device-transfer-v1',
    'accountId': id,
    'username': owner,
    'candidateHash': sha256.convert(fresh.publicKey).toString(),
    'newIdentityKey': base64Encode(fresh.publicKey),
    'nonce': 'b' * 64,
    'issuedAt': now - 1,
    'expiresAt': now + 120000,
    'fromEpoch': 0,
  };
  try {
    await body(owner, data);
  } finally {
    fresh.dispose();
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
  test(
    'v2 old device signs both independent domains for the same candidate',
    () async {
      await fixture((owner, data) async {
        final request = DeviceTransferRequest.parseV2(
          data,
          accountId: id,
          username: owner,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        final proof = await SignalE2eeService.instance
                .signConfirmedDeviceTransfer(
                  request,
                  userConfirmed: true,
                  isSessionCurrent: () => true,
                ),
            old = await SignalSecureStore(owner)
                .readExistingIdentityForTransfer();
        try {
          final approval = proof['approval'] as Map,
              certificate = proof['certificate'] as Map;
          expect(proof.keys.toSet(), {'approval', 'certificate'});
          expect(
            verifyDeviceTransferApproval(
              payload: Map<String, dynamic>.from(approval['payload'] as Map),
              signature: approval['signature'] as String,
              trustedOldIdentityKey: old.publicKey,
              accountId: id,
              username: owner,
              newIdentityKey: request.newIdentityKey,
              nonce: request.nonce,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            ),
            isTrue,
          );
          final verified = verifyDeviceKeyTransition(
            payload: Map<String, dynamic>.from(certificate['payload'] as Map),
            signature: certificate['signature'] as String,
            trustedOldIdentityKey: old.publicKey,
            accountId: id,
            username: owner,
            storedEpoch: 0,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          expect(verified, isNotNull);
          expect(verified!.newIdentityKey, request.newIdentityKey);
        } finally {
          old.dispose();
        }
      });
    },
  );
  test(
    'legacy request still produces only the original approval envelope',
    () async {
      await fixture((owner, data) async {
        data.remove('fromEpoch');
        final request = DeviceTransferRequest.parse(
          data,
          accountId: id,
          username: owner,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        final proof = await SignalE2eeService.instance
            .signConfirmedDeviceTransfer(
              request,
              userConfirmed: true,
              isSessionCurrent: () => true,
            );
        expect(proof.keys.toSet(), {'payload', 'signature'});
      });
    },
  );
  test(
    'v2 epoch is mandatory bounded and does not enter the v1 signed payload',
    () async {
      await fixture((owner, data) async {
        final request = DeviceTransferRequest.parseV2(
          data,
          accountId: id,
          username: owner,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        expect(request.fromEpoch, 0);
        expect(request.data.containsKey('fromEpoch'), isFalse);
        for (final epoch in [-1, 1.5, 9007199254740991]) {
          expect(
            DeviceTransferRequest.parseV2(
              {...data, 'fromEpoch': epoch},
              accountId: id,
              username: owner,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            ),
            isNull,
          );
        }
        expect(
          DeviceTransferRequest.parse(
            data,
            accountId: id,
            username: owner,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          ),
          isNull,
        );
      });
    },
  );
  test(
    'old device requires explicit consent before either proof is released',
    () async {
      await fixture((owner, data) async {
        final request = DeviceTransferRequest.parseV2(
          data,
          accountId: id,
          username: owner,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        await expectLater(
          SignalE2eeService.instance.signConfirmedDeviceTransfer(
            request,
            userConfirmed: false,
            isSessionCurrent: () => true,
          ),
          throwsStateError,
        );
      });
    },
  );
  test(
    'session change during secure key read prevents proof release',
    () async {
      await fixture((owner, data) async {
        final request = DeviceTransferRequest.parseV2(
          data,
          accountId: id,
          username: owner,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        )!;
        var current = true;
        scheduleMicrotask(() => current = false);
        await expectLater(
          SignalE2eeService.instance.signConfirmedDeviceTransfer(
            request,
            userConfirmed: true,
            isSessionCurrent: () => current,
          ),
          throwsStateError,
        );
      });
    },
  );
}
