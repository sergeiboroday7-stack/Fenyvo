import 'package:flutter_test/flutter_test.dart';
import '../lib/services/message_status_transition.dart';

void main() {
  List<Map<String, dynamic>> history(String status) => [
        <String, dynamic>{
          'id': 'm1',
          'from': 'alice',
          'to': 'bob',
          'isMe': true,
          'status': status,
          'text': 'encrypted message metadata',
        },
      ];

  List<Map<String, dynamic>>? update(
    List<Map<String, dynamic>> messages,
    String type, {
    String from = 'alice',
    String to = 'bob',
    String id = 'm1',
  }) =>
      applyMessageStatusTransition(
        messages: messages,
        currentUser: 'alice',
        peer: 'bob',
        messageId: id,
        eventType: type,
        from: from,
        to: to,
      );

  test('delivered updates a sent message', () {
    final original = history('sent');
    final changed = update(original, 'message_delivered');
    expect(changed, isNotNull);
    expect(changed!.single['status'], 'delivered');
    expect(original.single['status'], 'sent');
  });

  test('read updates a delivered message', () {
    final changed = update(history('delivered'), 'message_read');
    expect(changed!.single['status'], 'read');
  });

  test('delivered cannot downgrade read', () {
    expect(update(history('read'), 'message_delivered'), isNull);
  });

  test('foreign event cannot modify history', () {
    expect(
      update(history('sent'), 'message_read', from: 'mallory'),
      isNull,
    );
    expect(
      update(history('sent'), 'message_read', to: 'mallory'),
      isNull,
    );
  });

  test('missing message cannot be acknowledged as updated', () {
    expect(
      update(history('sent'), 'message_read', id: 'missing'),
      isNull,
    );
  });
}