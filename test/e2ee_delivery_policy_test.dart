import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/e2ee_delivery_policy.dart';

void main() {
  const policy = E2eeDeliveryPolicy();

  group('Mandatory E2EE delivery policy', () {
    test('private message always requires encryption', () {
      expect(
        policy.requiresEncryption(isPrivateMessage: true),
        isTrue,
      );
    });

    test('private message cannot transmit without encryption', () {
      expect(
        policy.mayTransmit(
          isPrivateMessage: true,
          encryptionSucceeded: false,
        ),
        isFalse,
      );
    });

    test('encrypted private message can transmit', () {
      expect(
        policy.mayTransmit(
          isPrivateMessage: true,
          encryptionSucceeded: true,
        ),
        isTrue,
      );
    });

    test('legacy outbox message still requires encryption', () {
      expect(
        policy.mustEncryptOutboxMessage({
          'id': 'old-message',
          'to': 'recipient',
          'text': 'example',
        }),
        isTrue,
      );
    });

    test('explicit false marker cannot disable encryption', () {
      expect(
        policy.mustEncryptOutboxMessage({
          'id': 'legacy-message',
          'requiresE2ee': false,
        }),
        isTrue,
      );
    });
  });
}