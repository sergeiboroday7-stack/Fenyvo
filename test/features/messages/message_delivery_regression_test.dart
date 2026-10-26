import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/domain/message_identity.dart';
import 'package:fenyvo/services/message_chronology.dart';

void main() {
  group('Message delivery regression', () {
    test('repeated delivery with the same ID does not add a duplicate', () {
      final messages = <Map<String, dynamic>>[
        {
          'id': 'm100',
          'from': 'alice',
          'to': 'bob',
          'text': 'hello',
          'time': '2026-10-24T12:00:00Z',
        },
      ];

      final repeated = <String, dynamic>{
        'id': 'm100',
        'from': 'alice',
        'to': 'bob',
        'text': 'hello',
        'time': '2026-10-24T12:00:01Z',
      };

      if (!messages.any((m) => isSameStoredMessage(m, repeated))) {
        messages.add(repeated);
      }

      expect(messages.length, 1);
    });

    test('distinct IDs survive even with identical text and time', () {
      final messages = <Map<String, dynamic>>[
        {
          'id': 'm1',
          'from': 'alice',
          'to': 'bob',
          'text': 'hello',
          'time': '2026-10-24T12:00:00Z',
        },
      ];

      final second = <String, dynamic>{
        'id': 'm2',
        'from': 'alice',
        'to': 'bob',
        'text': 'hello',
        'time': '2026-10-24T12:00:00Z',
      };

      if (!messages.any((m) => isSameStoredMessage(m, second))) {
        messages.add(second);
      }

      expect(messages.length, 2);
    });

    test('confirmed time changes ordering without duplicating messages', () {
      final messages = <Map<String, dynamic>>[
        {
          'id': 'm1',
          'time': '2026-10-24T12:00:03Z',
        },
        {
          'id': 'm2',
          'time': '2026-10-24T12:00:02Z',
        },
      ];

      messages.first['time'] = '2026-10-24T12:00:01Z';
      MessageChronology.sort(messages);

      expect(messages.map((m) => m['id']).toList(), ['m1', 'm2']);
    });

    test('equal timestamps preserve original message order', () {
      final messages = <Map<String, dynamic>>[
        {
          'id': 'first',
          'time': '2026-10-24T12:00:00Z',
        },
        {
          'id': 'second',
          'time': '2026-10-24T12:00:00Z',
        },
      ];

      MessageChronology.sort(messages);

      expect(messages.map((m) => m['id']).toList(), ['first', 'second']);
    });
  });
}