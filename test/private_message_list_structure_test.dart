import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private message list is extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_list.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_list.dart';"),
      isTrue,
    );
    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(module.contains('Widget _buildMessages()'), isTrue);
    expect(chat.contains('Widget _buildMessages()'), isFalse);
  });

  test('Windows and mobile list behavior is preserved', () {
    final module = File('lib/widgets/private_message_list.dart')
        .readAsStringSync();

    expect(module.contains('Platform.isWindows'), isTrue);
    expect(module.contains('Scrollbar('), isTrue);
    expect(module.contains('_messageScrollController'), isTrue);
    expect(module.contains('_buildMessageListItem('), isTrue);
    expect(module.contains('_buildScrollToLatestButton('), isTrue);

    expect(RegExp(r'ListView\.builder\s*\(').allMatches(module).length, 2);
    expect(RegExp(r'reverse\s*:\s*true').allMatches(module).length, 2);
  });

  test('transport and composer remain in main screen', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_list.dart')
        .readAsStringSync();

    expect(chat.contains('Widget _buildMessageInput()'), isFalse);
    expect(
      File('lib/widgets/private_message_composer.dart')
          .readAsStringSync()
          .contains('Widget _buildMessageInput()'),
      isTrue,
    );
    expect(module.contains('Widget _buildMessageInput()'), isFalse);
    expect(module.contains('setState('), isFalse);
    expect(module.contains('SocketService.'), isFalse);
    expect(module.contains('StorageService.'), isFalse);
    expect(module.contains('_sendMessage('), isFalse);
  });
}
