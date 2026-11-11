import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/private_e2ee_edit_delivery_policy.dart';

void main() {
  const policy = PrivateE2eeEditDeliveryPolicy();

  final edit = <String, dynamic>{
    'kind': 'private_edit_v1',
    'id': 'edit_123456',
    'from': 'alice',
    'to': 'bob',
    'targetMessageId': 'msg_123456',
    'newText': 'Исправленный текст',
    'editedAt': '2026-11-08T18:00:00.000Z',
  };

  test('recognizes a valid encrypted edit operation', () {
    expect(policy.isEditOperation(edit), isTrue);
    expect(policy.isValidEditOperation(edit), isTrue);
  });

  test('ordinary messages are not edit operations', () {
    expect(policy.isEditOperation({
      'id': 'msg_123456',
      'text': 'Привет',
    }), isFalse);
  });

  test('ACK of edit is excluded from ordinary message history', () {
    expect(
      policy.suppressOrdinaryMessageForAck(
        queued: edit,
        acknowledgedId: 'edit_123456',
      ),
      isTrue,
    );
  });

  test('ACK for another ID is not mistaken for edit ACK', () {
    expect(
      policy.suppressOrdinaryMessageForAck(
        queued: edit,
        acknowledgedId: 'different_123',
      ),
      isFalse,
    );
  });

  test('edit retries require the dedicated encrypted sender', () {
    expect(policy.needsDedicatedRetry(edit), isTrue);
    expect(policy.blockOrdinaryMessageFallback(edit), isTrue);
  });

  test('malformed edit cannot be treated as valid operation', () {
    final invalid = Map<String, dynamic>.from(edit)
      ..['newText'] = '';
    expect(policy.isValidEditOperation(invalid), isFalse);
    expect(policy.blockOrdinaryMessageFallback(invalid), isTrue);
  });

  test('plaintext edit must never enter normal delivery', () {
    final invalid = Map<String, dynamic>.from(edit)
      ..['id'] = '';
    expect(policy.isValidEditOperation(invalid), isFalse);
    expect(policy.blockOrdinaryMessageFallback(invalid), isTrue);
  });
}