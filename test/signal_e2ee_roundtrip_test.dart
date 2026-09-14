import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await LibSignal.init();
  });

  test('Signal pre-key handshake and Double Ratchet round trip', () async {
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

    const firstText = 'Привет, это защищённое сообщение';
    final encrypted = await aliceCipher.encrypt(
      bobAddress,
      Uint8List.fromList(utf8.encode(firstText)),
    );
    expect(
      utf8.decode(encrypted.ciphertext, allowMalformed: true),
      isNot(contains(firstText)),
    );
    final decrypted = await bobCipher.decrypt(aliceAddress, encrypted);
    expect(utf8.decode(decrypted), firstText);

    const replyText = 'Ответ через Double Ratchet';
    final reply = await bobCipher.encrypt(
      aliceAddress,
      Uint8List.fromList(utf8.encode(replyText)),
    );
    expect(
      utf8.decode(await aliceCipher.decrypt(bobAddress, reply)),
      replyText,
    );

    final reloadedAlice = SignalSecureStore('alice-test');
    expect(await reloadedAlice.containsSession(bobAddress), isTrue);
    expect(aliceIdentity.publicKey, isNotEmpty);

    final aliceFingerprint = Fingerprint(
      iterations: 5200,
      version: 2,
      localIdentifier: utf8.encode('alice-test'),
      localPublicKey: aliceIdentity.publicKey,
      remoteIdentifier: utf8.encode('bob-test'),
      remotePublicKey: bobIdentity.publicKey,
    );
    final bobFingerprint = Fingerprint(
      iterations: 5200,
      version: 2,
      localIdentifier: utf8.encode('bob-test'),
      localPublicKey: bobIdentity.publicKey,
      remoteIdentifier: utf8.encode('alice-test'),
      remotePublicKey: aliceIdentity.publicKey,
    );
    expect(aliceFingerprint.displayString(), hasLength(60));
    expect(aliceFingerprint.displayString(), bobFingerprint.displayString());
    expect(
      fingerprintCompare(
        fingerprint1: aliceFingerprint.scannableEncoding(),
        fingerprint2: bobFingerprint.scannableEncoding(),
      ),
      isTrue,
    );
  });
}
