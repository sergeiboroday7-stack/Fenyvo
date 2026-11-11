import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal/libsignal.dart';

import '../lib/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('interrupted recovery restores trusted identity', () async {
    await LibSignal.init();

    final address = ProtocolAddress(name: 'test_peer', deviceId: 1);
    final original = PrivateKey.generate().getPublicKey();
    final replacement = PrivateKey.generate().getPublicKey();

    final first = SignalSecureStore('test_account_1320');
    await first.saveIdentity(address, original);

    await first.beginVerifiedPeerRecovery(
      address,
      null,
      original,
    );

    await first.deleteRemoteIdentity(address);
    await first.saveIdentity(address, replacement);

    // Simulate reopening the store after interruption.
    final reopened = SignalSecureStore('test_account_1320');
    await reopened.restorePendingVerifiedPeerRecovery();

    final restored = await reopened.getIdentity(address);
    expect(restored, isNotNull);
    expect(restored!.equals(other: original), isTrue);
    expect(restored.equals(other: replacement), isFalse);

    // Recovery must be idempotent.
    await reopened.restorePendingVerifiedPeerRecovery();

    final again = await reopened.getIdentity(address);
    expect(again!.equals(other: original), isTrue);
  });

  test('pending recovery does not affect another account', () async {
    await LibSignal.init();

    final address = ProtocolAddress(name: 'test_peer', deviceId: 1);
    final original = PrivateKey.generate().getPublicKey();
    final unrelated = PrivateKey.generate().getPublicKey();

    final first = SignalSecureStore('test_account_A_1320');
    final second = SignalSecureStore('test_account_B_1320');

    await first.saveIdentity(address, original);
    await second.saveIdentity(address, unrelated);

    await first.beginVerifiedPeerRecovery(address, null, original);
    await first.deleteRemoteIdentity(address);

    await first.restorePendingVerifiedPeerRecovery();

    final preserved = await second.getIdentity(address);
    expect(preserved!.equals(other: unrelated), isTrue);
  });
}