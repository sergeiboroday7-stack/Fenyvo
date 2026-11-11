import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
  final module = File('lib/widgets/private_chatgpt_sheet.dart')
      .readAsStringSync();

  test('ChatGPT request uses three localized error keys', () {
    final start = chat.indexOf('Future<String> _requestChatGpt(');
    final closing = RegExp(
      r'^  [}]\r?$',
      multiLine: true,
    ).firstMatch(chat.substring(start));
    expect(closing, isNotNull);
    final end = start + closing!.end;
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final request = chat.substring(start, end);

    for (final key in ['emptyMessage', 'notConnected', 'timeout']) {
      expect(request.contains("_privateChatGptUiText('$key')"), isTrue);
    }
  });

  test('all error keys exist for RU UK EN', () {
    final dictionary = module
        .split('extension _PrivateChatGptSheet on _ChatScreenState {')
        .first;

    for (final key in ['emptyMessage', 'notConnected', 'timeout']) {
      expect(
        RegExp("'$key':").allMatches(dictionary).length,
        3,
        reason: 'Missing translations for $key',
      );
    }
  });

  test('request protocol and E2EE guards remain intact', () {
    expect(chat.contains('sendChatGptRequest('), isTrue);
    expect(chat.contains('_chatGptCompleters.remove(requestId)'), isTrue);
    expect(
      RegExp(r'PrivateExternalTextPolicy\.canSendMessage\s*\(')
          .allMatches(module)
          .length,
      2,
    );
  });
}
