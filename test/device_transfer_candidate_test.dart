import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';

void main() {
  test('concurrent candidate creation initializes native crypto once without account storage', () async {
    final service = SignalE2eeService.instance;
    expect(service.isReady, isFalse);
    final keys = await Future.wait([
      service.createDeviceTransferCandidate(),
      service.createDeviceTransferCandidate(),
    ]);
    try {
      expect(keys[0].publicKey.length, 33);
      expect(keys[1].publicKey.length, 33);
      expect(keys[0].publicKey, isNot(keys[1].publicKey));
      expect(service.isReady, isFalse);
    } finally {
      for (final key in keys) {
        key.dispose();
      }
    }
  });
}
