import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/e2ee_inbound_policy.dart';

void main() {
  const policy = E2eeInboundPolicy();

  group('Mandatory inbound E2EE', () {
    test('rejects plaintext network message', () {
      expect(
        policy.allowsNetworkMessage(e2eeMarker: false),
        isFalse,
      );
    });

    test('rejects packet without E2EE marker', () {
      expect(
        policy.allowsNetworkMessage(e2eeMarker: null),
        isFalse,
      );
    });

    test('rejects string pretending to be boolean true', () {
      expect(
        policy.allowsNetworkMessage(e2eeMarker: 'true'),
        isFalse,
      );
    });

    test('allows encrypted packet into Signal verification', () {
      expect(
        policy.allowsNetworkMessage(e2eeMarker: true),
        isTrue,
      );
    });
  });
}