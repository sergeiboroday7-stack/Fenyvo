import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Repaired group chat messages support RU UK EN', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'groupChatPhotoUnavailable': 'Фото недоступно',
        'groupChatVideoUnavailable': 'Видео недоступно',
        'groupChatSaveFailed': 'Не удалось сохранить сообщение.',
      },
      'uk': {
        'groupChatPhotoUnavailable': 'Фото недоступне',
        'groupChatVideoUnavailable': 'Відео недоступне',
        'groupChatSaveFailed': 'Не вдалося зберегти повідомлення.',
      },
      'en': {
        'groupChatPhotoUnavailable': 'Photo unavailable',
        'groupChatVideoUnavailable': 'Video unavailable',
        'groupChatSaveFailed': 'Could not save the message.',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      final forwarded = language
          .text('groupChatForwardedFrom')
          .replaceAll('{group}', 'GroupOne')
          .replaceAll('{user}', 'UserTwo');

      expect(forwarded, contains('GroupOne'));
      expect(forwarded, contains('UserTwo'));
      expect(forwarded, isNot(contains('{group}')));
      expect(forwarded, isNot(contains('{user}')));

      expect(language.text('groupCallVoiceMessage'), isNotEmpty);
      expect(language.text('groupCallMediaServerUnavailable'), isNotEmpty);
    }

    await language.select('de');
    expect(language.text('groupChatPhotoUnavailable'), 'Photo unavailable');

    await language.select('system');
  });
}
