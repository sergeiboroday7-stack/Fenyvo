import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop message menu is extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final menu = File('lib/widgets/private_desktop_message_context_menu.dart')
        .readAsStringSync();

    expect(
      chat.contains(
        "part '../widgets/private_desktop_message_context_menu.dart';",
      ),
      isTrue,
    );
    expect(
      menu.contains('Future<void> _showDesktopMessageContextMenu('),
      isTrue,
    );
    expect(
      chat.contains('Future<void> _showDesktopMessageContextMenu('),
      isFalse,
    );
    expect(chat.contains('Future<void> _showMessageActionMenu('), isTrue);
  });

  test('ownership and E2EE visibility guards remain', () {
    final menu = File('lib/widgets/private_desktop_message_context_menu.dart')
        .readAsStringSync();
    final compact = menu.replaceAll(RegExp(r'\s+'), '');

    expect(
      compact.contains('if(isMe&&forwardedFrom.isEmpty&&!isE2ee)'),
      isTrue,
    );
    expect(
      compact.contains("if(isMe)_buildDesktopMessageContextItem("),
      isTrue,
    );
    expect(RegExp(r'if\s*\(\s*!isE2ee\s*\)').allMatches(menu).length, 2);
    expect(menu.contains('_deleteMessageForEveryone(message)'), isTrue);
    expect(menu.contains('_deleteMessageForMe(message)'), isTrue);
    expect(menu.contains('SocketService.instance.send'), isFalse);
    expect(menu.contains('StorageService.'), isFalse);
  });
}
