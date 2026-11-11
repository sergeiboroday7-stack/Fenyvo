import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';
import 'package:fenyvo/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PreKey identifiers are not reused after exhaustion', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    const owner = 'prekey-allocator-regression';
    final service = SignalE2eeService.instance;
    await service.initializeForUser(owner);
    final store = SignalSecureStore(owner);

    final beforeClassic = (await store.getAllPreKeyIds()).toSet();
    final beforeKyber = (await store.getAllKyberPreKeyIds()).toSet();

    expect(beforeClassic, hasLength(24));
    expect(beforeKyber, hasLength(24));

    for (final id in beforeClassic) {
      await store.removePreKey(id);
    }
    for (final id in beforeKyber) {
      await store.removeKyberPreKey(id);
    }

    await service.createPublicBundle();

    final afterClassic = (await store.getAllPreKeyIds()).toSet();
    final afterKyber = (await store.getAllKyberPreKeyIds()).toSet();

    expect(afterClassic, hasLength(24));
    expect(afterKyber, hasLength(24));
    expect(afterClassic.intersection(beforeClassic), isEmpty);
    expect(afterKyber.intersection(beforeKyber), isEmpty);
  });
}