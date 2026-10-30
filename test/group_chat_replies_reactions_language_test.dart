import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group reactions replies and edited labels RU UK EN', () async {
    SharedPreferences.setMockInitialValues({});

    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupReactionChoose': 'Выберите реакцию',
        'groupMessageFallback': 'Сообщение',
        'groupReplyFallback': 'Ответ',
        'groupReplyCancel': 'Отменить ответ',
        'groupMessageEditedPrefix': 'изменено • ',
      },
      'uk': {
        'groupReactionChoose': 'Виберіть реакцію',
        'groupMessageFallback': 'Повідомлення',
        'groupReplyFallback': 'Відповідь',
        'groupReplyCancel': 'Скасувати відповідь',
        'groupMessageEditedPrefix': 'змінено • ',
      },
      'en': {
        'groupReactionChoose': 'Choose a reaction',
        'groupMessageFallback': 'Message',
        'groupReplyFallback': 'Reply',
        'groupReplyCancel': 'Cancel reply',
        'groupMessageEditedPrefix': 'edited • ',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      final edited = language.text('groupMessageEditedPrefix') + '14:30';

      expect(edited, contains(' • '));
      expect(edited, endsWith('14:30'));
    }

    await language.select('de');

    expect(language.text('groupReactionChoose'), 'Choose a reaction');
    expect(language.text('groupMessageFallback'), 'Message');
    expect(language.text('groupMessageEditedPrefix'), 'edited • ');

    await language.select('system');
  });
}
