import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/domain/message_date.dart';

void main() {
  group('Message calendar day', () {
    test('same date with different time', () {
      expect(
        isSameMessageCalendarDay(
          DateTime(2026, 10, 24, 0, 1),
          DateTime(2026, 10, 24, 23, 59),
        ),
        isTrue,
      );
    });

    test('different days', () {
      expect(
        isSameMessageCalendarDay(
          DateTime(2026, 10, 24, 23, 59),
          DateTime(2026, 10, 25, 0, 1),
        ),
        isFalse,
      );
    });


    test('parses UTC ISO timestamp', () {
      final date = parseMessageLocalDate('2026-10-24T12:30:00Z');
      expect(date, isNotNull);
      expect(date!.toUtc(), DateTime.utc(2026, 10, 24, 12, 30));
    });

    test('invalid timestamp returns null', () {
      expect(parseMessageLocalDate('invalid-date'), isNull);
    });

    test('null timestamp returns null', () {
      expect(parseMessageLocalDate(null), isNull);
    });
    test('different years', () {
      expect(
        isSameMessageCalendarDay(
          DateTime(2025, 12, 31),
          DateTime(2026, 12, 31),
        ),
        isFalse,
      );
    });
  });
}