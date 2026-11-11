import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('display widgets are extracted into a Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_display_widgets.dart';"),
      isTrue,
    );

    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);

    expect(module.contains('extension _PrivateMessageDisplayWidgets'), isTrue);
  });

  test('contact and call history builders are relocated', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();

    for (final name in ['_buildSharedContactCard', '_buildCallHistoryBubble']) {
      expect(RegExp(r'Widget\s+' + name + r'\s*\(').hasMatch(module), isTrue);

      expect(RegExp(r'Widget\s+' + name + r'\s*\(').hasMatch(chat), isFalse);
    }
  });

  test('display module does not own message mutations', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_display_widgets.dart')
        .readAsStringSync();

    expect(chat.contains('Widget _buildMessageBubble('), isFalse);
    expect(
      File('lib/widgets/private_message_bubble.dart')
          .readAsStringSync()
          .contains('Widget _buildMessageBubble('),
      isTrue,
    );
    expect(chat.contains('Widget _buildMessages('), isFalse);
    expect(
      File('lib/widgets/private_message_list.dart')
          .readAsStringSync()
          .contains('Widget _buildMessages('),
      isTrue,
    );

    expect(module.contains('setState('), isFalse);
    expect(module.contains('StorageService.'), isFalse);
    expect(module.contains('SocketService.instance.send'), isFalse);
    expect(module.contains('void _sendMessage('), isFalse);
  });
}
