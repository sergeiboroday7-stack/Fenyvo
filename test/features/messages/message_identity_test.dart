import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/domain/message_identity.dart';

void main() {
  group('Message identity', () {
    test('matching IDs are duplicates', () {
      expect(
        isSameStoredMessage(
          {'id': 'm1', 'text': 'first'},
          {'id': 'm1', 'text': 'updated'},
        ),
        isTrue,
      );
    });

    test('different IDs are distinct', () {
      expect(
        isSameStoredMessage(
          {'id': 'm1', 'text': 'hello'},
          {'id': 'm2', 'text': 'hello'},
        ),
        isFalse,
      );
    });

    test('missing ID does not automatically match an identified message', () {
      final legacy = {
        'from': 'alice',
        'to': 'bob',
        'text': 'hello',
        'time': '2026-10-24T12:00:00Z',
      };

      expect(
        isSameStoredMessage(legacy, {'id': 'm1', ...legacy}),
        isFalse,
      );
    });

    test('identical legacy messages are recognized', () {
      final legacy = {
        'from': 'alice',
        'to': 'bob',
        'text': 'hello',
        'time': '2026-10-24T12:00:00Z',
      };

      expect(isSameStoredMessage(legacy, Map.of(legacy)), isTrue);
    });

    test('legacy messages with different timestamps remain distinct', () {
      expect(
        isSameStoredMessage(
          {'from': 'a', 'to': 'b', 'text': 'hi', 'time': 't1'},
          {'from': 'a', 'to': 'b', 'text': 'hi', 'time': 't2'},
        ),
        isFalse,
      );
    });
  });
}