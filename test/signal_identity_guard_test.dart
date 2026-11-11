import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:fenyvo/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await LibSignal.init();
  });

  test('remote identity cannot change without explicit verification', () async {
    final store = SignalSecureStore('step1207-local');
    final first = SignalSecureStore('step1207-first');
    final second = SignalSecureStore('step1207-second');

    final firstIdentity = await first.ensureIdentity();
    final secondIdentity = await second.ensureIdentity();

    final firstKey = PublicKey.deserialize(
      bytes: firstIdentity.publicKey,
    );
    final secondKey = PublicKey.deserialize(
      bytes: secondIdentity.publicKey,
    );

    expect(firstKey.equals(other: secondKey), isFalse);

    final peer = ProtocolAddress(
      name: 'step1207-peer',
      deviceId: 1,
    );

    expect(await store.saveIdentity(peer, firstKey), isTrue);
    expect(await store.saveIdentity(peer, firstKey), isFalse);

    await expectLater(
      store.saveIdentity(peer, secondKey),
      throwsStateError,
    );

    final preserved = await store.getIdentity(peer);
    expect(preserved, isNotNull);
    expect(preserved!.equals(other: firstKey), isTrue);
  });
}