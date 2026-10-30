import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Empty group chat RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, List<String>>{
      'ru': ['Сообщений пока нет', 'Напишите первое сообщение в группу'],
      'uk': ['Повідомлень поки немає', 'Напишіть перше повідомлення в групу'],
      'en': ['No messages yet', 'Send the first message to the group'],
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);
      expect(language.text('groupEmptyTitle'), expected[code]![0]);
      expect(language.text('groupEmptySubtitle'), expected[code]![1]);
    }

    await language.select('de');
    expect(language.text('groupEmptyTitle'), 'No messages yet');
    expect(
      language.text('groupEmptySubtitle'),
      'Send the first message to the group',
    );

    await language.select('system');
  });
}
