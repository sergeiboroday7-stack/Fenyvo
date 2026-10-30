import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group chat repair labels RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'groupChatForward': 'Переслать',
        'groupChatSearchRecipients': 'Поиск получателей',
        'groupChatSearchGroup': 'Поиск по группе',
        'groupChatPreviousMatch': 'Предыдущее',
        'groupChatSearch': 'Поиск',
      },
      'uk': {
        'groupChatForward': 'Переслати',
        'groupChatSearchRecipients': 'Пошук одержувачів',
        'groupChatSearchGroup': 'Пошук у групі',
        'groupChatPreviousMatch': 'Попереднє',
        'groupChatSearch': 'Пошук',
      },
      'en': {
        'groupChatForward': 'Forward',
        'groupChatSearchRecipients': 'Search recipients',
        'groupChatSearchGroup': 'Search in group',
        'groupChatPreviousMatch': 'Previous',
        'groupChatSearch': 'Search',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);
      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }
    }

    await language.select('de');
    expect(language.text('groupChatForward'), 'Forward');
    expect(language.text('groupChatSearch'), 'Search');

    await language.select('system');
  });
}
