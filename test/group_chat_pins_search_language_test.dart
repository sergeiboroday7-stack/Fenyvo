import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group pins and search RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupPinLimit': 'В группе можно закрепить до 10 сообщений',
        'groupPinRemoved': 'Сообщение откреплено',
        'groupPinAdded': 'Сообщение закреплено',
        'groupSearchNextMatch': 'Следующее',
        'groupSearchClose': 'Закрыть поиск',
        'groupActionUnpin': 'Открепить',
      },
      'uk': {
        'groupPinLimit': 'У групі можна закріпити до 10 повідомлень',
        'groupPinRemoved': 'Повідомлення відкріплено',
        'groupPinAdded': 'Повідомлення закріплено',
        'groupSearchNextMatch': 'Наступний збіг',
        'groupSearchClose': 'Закрити пошук',
        'groupActionUnpin': 'Відкріпити',
      },
      'en': {
        'groupPinLimit': 'You can pin up to 10 messages in a group',
        'groupPinRemoved': 'Message unpinned',
        'groupPinAdded': 'Message pinned',
        'groupSearchNextMatch': 'Next match',
        'groupSearchClose': 'Close search',
        'groupActionUnpin': 'Unpin',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }
    }

    await language.select('de');
    expect(language.text('groupPinAdded'), 'Message pinned');
    expect(language.text('groupSearchClose'), 'Close search');
    expect(language.text('groupActionUnpin'), 'Unpin');

    await language.select('system');
  });
}
