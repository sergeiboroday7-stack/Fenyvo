import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'privateBubbleEdited',
    'privateBubbleReply',
    'privateBubbleCopy',
    'privateBubbleForward',
    'privateBubbleEdit',
    'privateBubbleReactionHeart',
  ];

  test('all six labels use localized text calls', () {
    final source = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    // Dart format may wrap member access and method arguments.
    // Ignore whitespace and accept an optional trailing comma.
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    for (final key in keys) {
      final call = RegExp(
        RegExp.escape("AppLanguageService.instance.text('$key'") + r',?\)',
      );

      expect(
        call.hasMatch(compact),
        isTrue,
        reason: 'Missing localized call: $key',
      );
    }
  });

  test('six keys exist in all three language dictionaries', () {
    final language = File('lib/services/app_language_service.dart')
        .readAsStringSync();

    for (final key in keys) {
      expect(
        RegExp("'$key':").allMatches(language).length,
        3,
        reason: 'Missing RU/UK/EN values for $key',
      );
    }
  });

  test('message actions and state wrapper remain connected', () {
    final source = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    for (final method in [
      '_sendReaction(',
      '_editMessage(',
      '_forwardMessage(',
      '_buildPrivateMediaBody(',
      '_updateMessageBubbleState(',
    ]) {
      expect(source.contains(method), isTrue, reason: method);
    }
  });

  test('UI module does not directly mutate storage or socket', () {
    final source = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    expect(source.contains('StorageService.'), isFalse);
    expect(source.contains('SocketService.'), isFalse);
    expect(RegExp(r'(?<![\w.])setState\s*\(').hasMatch(source), isFalse);
  });
}
