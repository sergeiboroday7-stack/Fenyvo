import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/domain/message_reactions.dart';

void main() {
  group('Message reactions', () {
    test('empty reactions', () {
      expect(countMessageReactions(<String>[]), isEmpty);
    });

    test('counts repeated reactions', () {
      final result = countMessageReactions([
        'like',
        'like',
        'fire',
      ]);

      expect(result['like'], 2);
      expect(result['fire'], 1);
    });

    test('preserves different reactions', () {
      final result = countMessageReactions([
        'heart',
        'fire',
        'heart',
        'smile',
      ]);

      expect(result.length, 3);
      expect(result['heart'], 2);
      expect(result['fire'], 1);
      expect(result['smile'], 1);
    });


    test('stored reactions accept only supported values', () {
      final message = <String, dynamic>{
        'reactions': <String, dynamic>{
          'alice': 'a',
          'bob': 'a',
          'charlie': 'unsupported',
        },
      };

      final result = parseStoredMessageReactions(
        message,
        <String>['a'],
      );

      expect(result['alice'], 'a');
      expect(result['bob'], 'a');
      expect(result.containsKey('charlie'), isFalse);
    });

    test('missing stored reactions produce empty result', () {
      final result = parseStoredMessageReactions(
        <String, dynamic>{},
        <String>['a'],
      );

      expect(result, isEmpty);
    });
    test('does not modify source collection', () {
      final source = <String>['heart', 'heart'];
      countMessageReactions(source);

      expect(source, ['heart', 'heart']);
    });
  });
}