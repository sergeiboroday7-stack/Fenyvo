import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group call banner RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});

    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupChatDefaultGroupName': 'Группа',
        'groupChatCallBannerTitle': 'Групповой видеозвонок',
        'groupChatCallReturn': 'Вернуться в звонок',
        'groupChatCallWaitingApproval': 'Ждём разрешения ведущего…',
        'groupChatCallReturnBroadcast': 'Вернуться в эфир',
        'groupChatCallWatch': 'Смотреть трансляцию и открыть чат',
        'groupChatSavedLocally': 'Добавлено в «Сохранённое» на этом устройстве',
      },
      'uk': {
        'groupChatDefaultGroupName': 'Група',
        'groupChatCallBannerTitle': 'Груповий відеодзвінок',
        'groupChatCallReturn': 'Повернутися до дзвінка',
        'groupChatCallWaitingApproval': 'Очікуємо дозволу ведучого…',
        'groupChatCallReturnBroadcast': 'Повернутися до ефіру',
        'groupChatCallWatch': 'Дивитися трансляцію та відкрити чат',
        'groupChatSavedLocally': 'Додано до «Збереженого» на цьому пристрої',
      },
      'en': {
        'groupChatDefaultGroupName': 'Group',
        'groupChatCallBannerTitle': 'Group video call',
        'groupChatCallReturn': 'Return to call',
        'groupChatCallWaitingApproval': 'Waiting for host approval…',
        'groupChatCallReturnBroadcast': 'Return to broadcast',
        'groupChatCallWatch': 'Watch broadcast and open chat',
        'groupChatSavedLocally': 'Added to Saved on this device',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      final label =
          '${language.text('groupChatCallBannerTitle')} · 2/4\n'
          '${language.text('groupChatCallReturn')}';

      expect(label, contains('2/4'));
      expect(label, contains('\n'));
      expect(label, contains(language.text('groupChatCallReturn')));
    }

    await language.select('de');

    expect(language.text('groupChatDefaultGroupName'), 'Group');
    expect(language.text('groupChatCallBannerTitle'), 'Group video call');
    expect(language.text('groupChatCallReturn'), 'Return to call');
    expect(
      language.text('groupChatSavedLocally'),
      'Added to Saved on this device',
    );

    await language.select('system');
  });
}
