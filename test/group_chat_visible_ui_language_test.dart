import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group chat visible labels RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'groupChatPlanCall': 'Запланировать звонок',
        'groupChatStartCallNow': 'Начать звонок сейчас',
        'groupChatMessagePlaceholder': 'Сообщение...',
        'groupCallFile': 'Файл',
      },
      'uk': {
        'groupChatPlanCall': 'Запланувати дзвінок',
        'groupChatStartCallNow': 'Почати дзвінок зараз',
        'groupChatMessagePlaceholder': 'Повідомлення...',
        'groupCallFile': 'Файл',
      },
      'en': {
        'groupChatPlanCall': 'Schedule a call',
        'groupChatStartCallNow': 'Start a call now',
        'groupChatMessagePlaceholder': 'Message...',
        'groupCallFile': 'File',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      for (final key in [
        'groupChatPlanCallHint',
        'groupChatStartCallHint',
        'groupChatAudioCallTooltip',
        'groupChatVideoCallTooltip',
        'groupCallPhoto',
        'groupCallVideo',
        'groupCallParticipants',
        'groupAddTitle',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }
    }

    await language.select('de');
    expect(language.text('groupChatPlanCall'), 'Schedule a call');
    expect(language.text('groupChatMessagePlaceholder'), 'Message...');

    await language.select('system');
  });
}
