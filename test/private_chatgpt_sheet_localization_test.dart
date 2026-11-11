import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/widgets/private_chatgpt_sheet.dart')
      .readAsStringSync();

  // Only inspect the localization helper, not the actionLabels map.
  final helper = source
      .split('extension _PrivateChatGptSheet on _ChatScreenState {')
      .first;

  test('ChatGPT UI contains RU UK EN dictionaries', () {
    for (final code in ['ru', 'uk', 'en']) {
      expect(helper.contains("'$code': {"), isTrue);
    }
  });

  test('all 14 keys exist exactly three times in dictionaries', () {
    for (final key in [
      'reply',
      'explain',
      'rewrite',
      'shorter',
      'title',
      'message',
      'chooseAction',
      'thinking',
      'run',
      'result',
      'copied',
      'copy',
      'insert',
      'disclosure',
    ]) {
      expect(
        RegExp("'$key':").allMatches(helper).length,
        3,
        reason: 'Localization key: $key',
      );
    }
  });

  test('language follows user or system setting', () {
    expect(helper.contains('AppLanguageService.instance.code.value'), isTrue);
    expect(helper.contains('platformDispatcher.locale.languageCode'), isTrue);
    expect(helper.contains("values['en']!"), isTrue);
  });

  test('E2EE guards and AI request behavior remain', () {
    expect(
      RegExp(r'PrivateExternalTextPolicy\.canSendMessage\s*\(')
          .allMatches(source)
          .length,
      2,
    );
    expect(source.contains('_requestChatGpt('), isTrue);
    expect(source.contains('_messageController.text = value'), isTrue);
    expect(source.contains('_messageFocusNode.requestFocus()'), isTrue);
  });
}
