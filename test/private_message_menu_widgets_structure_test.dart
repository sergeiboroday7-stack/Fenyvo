import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message menu widgets are in a Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_menu_widgets.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_menu_widgets.dart';"),
      isTrue,
    );
    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);

    for (final name in [
      '_buildMessageMenuItem',
      '_buildDesktopQuickMessageAction',
    ]) {
      expect(module.contains('Widget $name('), isTrue);
      expect(chat.contains('Widget $name('), isFalse);
    }
  });

  test('message operations remain in ChatScreen', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_message_menu_widgets.dart')
        .readAsStringSync();

    expect(chat.contains('Future<void> _showMessageActionMenu('), isTrue);
    expect(
      File('lib/widgets/private_desktop_message_context_menu.dart')
          .readAsStringSync()
          .contains('Future<void> _showDesktopMessageContextMenu('),
      isTrue,
    );
    expect(module.contains('SocketService.'), isFalse);
    expect(module.contains('StorageService.'), isFalse);
    expect(module.contains('setState('), isFalse);
  });

  test('menu keeps callbacks without implementing their actions', () {
    final module = File('lib/widgets/private_message_menu_widgets.dart')
        .readAsStringSync();

    expect(module.contains('VoidCallback onTap'), isTrue);
    expect(module.contains('onTap: onTap'), isTrue);
    expect(module.contains('_sendReaction('), isFalse);
  });
}
