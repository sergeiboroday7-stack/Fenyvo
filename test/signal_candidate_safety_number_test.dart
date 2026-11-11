import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';
import 'package:fenyvo/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('candidate safety number never changes trusted identity', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    const owner = 'candidate-safety-owner';
    const peer = 'candidate-safety-peer';
    final service = SignalE2eeService.instance;
    await service.initializeForUser(owner);

    final a = IdentityKeyPair.generate();
    final b = IdentityKeyPair.generate();
    final first = await service.candidateSafetyNumber(
      peer, base64Encode(a.publicKey),
    );
    final repeated = await service.candidateSafetyNumber(
      peer, base64Encode(a.publicKey),
    );
    final changed = await service.candidateSafetyNumber(
      peer, base64Encode(b.publicKey),
    );
    expect(first.display.replaceAll(' ', ''), hasLength(60));
    expect(first.display, repeated.display);
    expect(first.display, isNot(changed.display));
    expect(first.scannable, repeated.scannable);
    final store = SignalSecureStore(owner);
    final address = ProtocolAddress(name: peer, deviceId: 1);
    expect(await store.getIdentity(address), isNull);
    expect(await store.containsSession(address), isFalse);
  });
}
