import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final methods = <String>[
    '_buildHeartIcon',
    '_buildMessageStatus',
    '_buildMessageListItem',
  ];

  test('three display methods are extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();

    for (final name in methods) {
      expect(module.contains('Widget $name('), isTrue);
      expect(chat.contains('Widget $name('), isFalse);
    }
  });

  test('display module retains presentation dependencies', () {
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();

    expect(module.contains('_buildMessageBubble('), isTrue);
    expect(module.contains('_messageItemKey('), isTrue);
    expect(module.contains('_getMessageId('), isTrue);
  });

  test('display module does not own message mutations', () {
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();

    expect(module.contains('setState('), isFalse);
    expect(module.contains('StorageService.'), isFalse);
    expect(module.contains('SocketService.instance.send'), isFalse);
    expect(chat.contains('void _sendMessage('), isTrue);
    expect(chat.contains('void _sendReaction('), isTrue);
  });
}
