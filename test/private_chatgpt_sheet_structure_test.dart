import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatGPT sheet is extracted into its own Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final part = File('lib/widgets/private_chatgpt_sheet.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_chatgpt_sheet.dart';"),
      isTrue,
    );
    expect(part.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(
      part.contains(
        'Future<void> _showChatGptSheet(Map<String, dynamic> message)',
      ),
      isTrue,
    );
    expect(
      chat.contains(
        'Future<void> _showChatGptSheet(Map<String, dynamic> message)',
      ),
      isFalse,
    );
  });

  test('ChatGPT keeps E2EE guards and compose actions', () {
    final part = File('lib/widgets/private_chatgpt_sheet.dart')
        .readAsStringSync();

    expect(
      RegExp(r'PrivateExternalTextPolicy\.canSendMessage\s*\(')
          .allMatches(part)
          .length,
      2,
    );

    expect(RegExp(r'_ChatScreenState\._gold\b').allMatches(part).length, 12);

    for (final requiredText in [
      '_requestChatGpt(',
      '_messageController.text = value',
      '_messageFocusNode.requestFocus()',
      "action: 'reply'",
      "action: 'explain'",
      "action: 'rewrite'",
      "action: 'shorter'",
    ]) {
      expect(part.contains(requiredText), isTrue);
    }
  });
}
