import 'package:flutter_test/flutter_test.dart';
import '../lib/services/message_status_merge.dart';

void main() {
  Map<String, dynamic> message(
    String id,
    String status, {
    String from = 'alice',
    String to = 'bob',
    String text = 'hello',
  }) =>
      <String, dynamic>{
        'id': id,
        'from': from,
        'to': to,
        'status': status,
        'text': text,
      };

  test('read is not overwritten by stale sent', () {
    final result = preserveMessageStatus(
      incoming: [message('m1', 'sent')],
      persisted: [message('m1', 'read')],
    );

    expect(result.single['status'], 'read');
  });

  test('delivered is not overwritten by stale sent', () {
    final result = preserveMessageStatus(
      incoming: [message('m1', 'sent')],
      persisted: [message('m1', 'delivered')],
    );

    expect(result.single['status'], 'delivered');
  });

  test('newer read is retained', () {
    final result = preserveMessageStatus(
      incoming: [message('m1', 'read')],
      persisted: [message('m1', 'delivered')],
    );

    expect(result.single['status'], 'read');
  });

  test('same id with different sender is not merged', () {
    final result = preserveMessageStatus(
      incoming: [message('m1', 'sent', from: 'carol')],
      persisted: [message('m1', 'read')],
    );

    expect(result.single['status'], 'sent');
  });

  test('deleted messages are not restored', () {
    final result = preserveMessageStatus(
      incoming: [],
      persisted: [message('m1', 'read')],
    );

    expect(result, isEmpty);
  });

  test('inputs are unchanged and other fields are preserved', () {
    final incoming = [message('m1', 'sent', text: 'edited')];
    final persisted = [message('m1', 'read', text: 'old')];

    final result = preserveMessageStatus(
      incoming: incoming,
      persisted: persisted,
    );

    expect(result.single['status'], 'read');
    expect(result.single['text'], 'edited');
    expect(incoming.single['status'], 'sent');
    expect(persisted.single['text'], 'old');
  });

  test('ambiguous duplicate identities are not merged', () {
    final result = preserveMessageStatus(
      incoming: [message('m1', 'sent')],
      persisted: [
        message('m1', 'read'),
        message('m1', 'delivered'),
      ],
    );

    expect(result.single['status'], 'sent');
  });
}