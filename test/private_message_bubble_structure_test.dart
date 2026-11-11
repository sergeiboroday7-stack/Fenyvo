import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message bubble is implemented in its own Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_bubble.dart';"),
      isTrue,
    );
    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(module.contains('Widget _buildMessageBubble('), isTrue);
    expect(chat.contains('Widget _buildMessageBubble('), isFalse);
  });

  test('hover setState is delegated to ChatScreen State', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    expect(
      chat.contains('void _updateMessageBubbleState(VoidCallback update)'),
      isTrue,
    );
    expect(
      RegExp(r'_updateMessageBubbleState\s*\(').allMatches(module).length,
      2,
    );
    expect(RegExp(r'(?<![\w.])setState\s*\(').hasMatch(module), isFalse);
  });

  test('all existing message operations remain connected', () {
    final module = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    for (final name in [
      '_buildCallHistoryBubble(',
      '_buildSharedContactCard(',
      '_buildPrivateMediaBody(',
      '_buildReactionRow(',
      '_buildMessageStatus(',
      '_showMessageActionMenu(',
      '_sendReaction(',
      '_editMessage(',
      '_forwardMessage(',
    ]) {
      expect(module.contains(name), isTrue, reason: name);
    }
  });

  test('the bubble contains no direct socket or storage calls', () {
    final module = File('lib/widgets/private_message_bubble.dart')
        .readAsStringSync();

    expect(module.contains('SocketService.'), isFalse);
    expect(module.contains('StorageService.'), isFalse);
  });
}
