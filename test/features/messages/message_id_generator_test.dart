import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/domain/message_id_generator.dart';

void main() {
  group('Message ID generator', () {
    test('returns nonempty string IDs', () {
      final id = MessageIdGenerator.generate();

      expect(id, isNotEmpty);
      expect(RegExp(r'^\d+-[0-9a-f]{16}$').hasMatch(id), isTrue);
    });

    test('generates 10000 distinct IDs', () {
      final ids = <String>{};

      for (var i = 0; i < 10000; i++) {
        ids.add(MessageIdGenerator.generate());
      }

      expect(ids.length, 10000);
    });

    test('new IDs work with message identity comparison', () {
      final firstId = MessageIdGenerator.generate();
      final secondId = MessageIdGenerator.generate();

      expect(firstId, isNot(secondId));
    });
  });
}