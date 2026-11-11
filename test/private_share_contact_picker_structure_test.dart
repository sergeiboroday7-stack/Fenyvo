import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('share contact picker is isolated in its own part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final part = File('lib/widgets/private_share_contact_picker.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_share_contact_picker.dart';"),
      isTrue,
    );
    expect(part.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(
      part.contains('Future<void> _showShareContactPicker() async'),
      isTrue,
    );
    expect(
      chat.contains('Future<void> _showShareContactPicker() async'),
      isFalse,
    );
  });

  test('registered user request and localized contact UI survive', () {
    final part = File('lib/widgets/private_share_contact_picker.dart')
        .readAsStringSync();

    for (final symbol in [
      'SocketService.instance.getRegisteredUsers()',
      '_registeredUsersCompleter',
      'showModalBottomSheet<String>',
      "AppLanguageService.instance.text('chatContactsNotFound')",
      "AppLanguageService.instance.text('chatShareContact')",
      '_ChatScreenState._gold',
    ]) {
      expect(part.contains(symbol), isTrue, reason: symbol);
    }
  });
}
