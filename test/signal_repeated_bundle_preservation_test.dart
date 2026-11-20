import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';
import 'package:fenyvo/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await LibSignal.init();
  });

  test('repeated bundle preserves existing Signal session', () async {
    final service = SignalE2eeService.instance;
    final owner = 'repeat-bundle-owner';
    final peer = 'repeat-bundle-peer';
    await service.initializeForUser(owner);
    final store = SignalSecureStore(owner);
    final identity = IdentityKeyPair.generate();
    final pre = PrivateKey.generate().getPublicKey().serialize();
    final signed = PrivateKey.generate().getPublicKey().serialize();
    final kyber = KyberKeyPair.generate().getPublicKey().serialize();
    final data = <String, dynamic>{
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
    final address = ProtocolAddress(name: peer, deviceId: 1);
    try {
      await service.processRemoteBundle(peer, data);
      expect(await store.containsSession(address), isTrue);
      final before = (await store.loadSession(address))!.serialize();
      await service.processRemoteBundle(peer, data);
      final after = (await store.loadSession(address))!.serialize();
      expect(after, orderedEquals(before));
      final encrypted = await service.encrypt(peer, {'text': 'preserved'});
      expect(encrypted['e2eeProtocol'], 'signal');
    } finally {
      identity.dispose();
    }
  });
}
