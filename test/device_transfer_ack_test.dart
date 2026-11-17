import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/device_transfer_ack.dart';

void main() {
  test(
    'only exact nonce and current scope acknowledge proof receipt',
    () async {
      final gate = DeviceTransferAck(), scope = Object();
      final result = gate.begin(
        scope: scope,
        nonce: 'a' * 64,
        timeout: const Duration(seconds: 1),
      );
      expect(
        gate.receive({'transferNonce': 'a' * 64}, scope: Object()),
        isFalse,
      );
      expect(gate.receive({'transferNonce': 'b' * 64}, scope: scope), isFalse);
      expect(
        gate.receive({'transferNonce': 'a' * 64, 'extra': true}, scope: scope),
        isFalse,
      );
      expect(gate.receive({'transferNonce': 'a' * 64}, scope: scope), isTrue);
      expect(await result, isTrue);
      expect(gate.waiting, isFalse);
    },
  );
  test('timeout is not acknowledgement and cannot be revived', () async {
    final gate = DeviceTransferAck(), scope = Object();
    final result = gate.begin(
      scope: scope,
      nonce: 'a' * 64,
      timeout: const Duration(milliseconds: 1),
    );
    expect(await result, isFalse);
    expect(gate.receive({'transferNonce': 'a' * 64}, scope: scope), isFalse);
  });
  test(
    'cancel resolves pending false and old ACK cannot satisfy a new scope',
    () async {
      final gate = DeviceTransferAck(), old = Object(), next = Object();
      final first = gate.begin(
        scope: old,
        nonce: 'a' * 64,
        timeout: const Duration(seconds: 1),
      );
      gate.cancel();
      expect(await first, isFalse);
      final second = gate.begin(
        scope: next,
        nonce: 'b' * 64,
        timeout: const Duration(seconds: 1),
      );
      expect(gate.receive({'transferNonce': 'a' * 64}, scope: old), isFalse);
      gate.cancel();
      expect(await second, isFalse);
    },
  );
  test(
    'simultaneous ACK requests do not replace the pending operation',
    () async {
      final gate = DeviceTransferAck();
      final first = gate.begin(
        scope: Object(),
        nonce: 'a' * 64,
        timeout: const Duration(seconds: 1),
      );
      expect(
        () => gate.begin(
          scope: Object(),
          nonce: 'b' * 64,
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );
      gate.cancel();
      expect(await first, isFalse);
    },
  );
}
