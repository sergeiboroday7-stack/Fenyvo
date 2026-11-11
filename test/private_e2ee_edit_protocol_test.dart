import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/private_e2ee_edit_protocol.dart';

void main() {
  final time = DateTime.utc(2026, 11, 8, 12);

  Map<String, dynamic> payload() =>
      PrivateE2eeEditProtocol.create(
        eventId: 'edit_event_12345',
        from: 'alice',
        to: 'bob',
        targetMessageId: 'original_12345',
        newText: 'Updated message',
        editedAt: time,
      );

  Map<String, dynamic> original() => {
    'id': 'original_12345',
    'from': 'alice',
    'to': 'bob',
    'text': 'Old message',
    'e2ee': true,
  };

  bool allowed(
    Map<String, dynamic> p,
    Map<String, dynamic> m, {
    String authenticatedFrom = 'alice',
  }) =>
      PrivateE2eeEditProtocol.canApply(
        payload: p,
        original: m,
        authenticatedFrom: authenticatedFrom,
        localUser: 'bob',
        peer: 'alice',
      );

  test('creates an encrypted-operation payload shape', () {
    expect(payload()['kind'], 'private_edit_v1');
    expect(payload()['targetMessageId'], 'original_12345');
  });

  test('valid encrypted operation can update original', () {
    expect(allowed(payload(), original()), isTrue);
  });

  test('rejects forged authenticated sender', () {
    expect(
      allowed(payload(), original(), authenticatedFrom: 'mallory'),
      isFalse,
    );
  });

  test('rejects edit of another authors message', () {
    final m = original()..['from'] = 'mallory';
    expect(allowed(payload(), m), isFalse);
  });

  test('rejects edit of plaintext original', () {
    final m = original()..['e2ee'] = false;
    expect(allowed(payload(), m), isFalse);
  });

  test('rejects another target ID', () {
    final p = payload()..['targetMessageId'] = 'another_message';
    expect(allowed(p, original()), isFalse);
  });

  test('rejects replay of same event', () {
    final m = original()..['lastEditEventId'] = 'edit_event_12345';
    expect(allowed(payload(), m), isFalse);
  });

  test('rejects older operation', () {
    final m = original()
      ..['editedAt'] = DateTime.utc(2026, 11, 8, 13).toIso8601String();
    expect(allowed(payload(), m), isFalse);
  });

  test('rejects oversized text', () {
    expect(
      () => PrivateE2eeEditProtocol.create(
        eventId: 'edit_event_12345',
        from: 'alice',
        to: 'bob',
        targetMessageId: 'original_12345',
        newText: 'x' * 4001,
        editedAt: time,
      ),
      throwsArgumentError,
    );
  });

  test('rejects operation masquerading as original message', () {
    final p = payload()..['id'] = 'original_12345';
    expect(allowed(p, original()), isFalse);
  });
}