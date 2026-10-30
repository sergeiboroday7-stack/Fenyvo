import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group message actions RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});

    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupActionSave': 'Сохранить',
        'groupActionReply': 'Ответить',
        'groupActionReaction': 'Реакция',
        'groupActionCopy': 'Копировать',
        'groupActionUnpin': 'Открепить',
        'groupActionPin': 'Закрепить',
        'groupActionEdit': 'Редактировать',
        'groupActionDeleteForAll': 'Удалить у всех',
      },
      'uk': {
        'groupActionSave': 'Зберегти',
        'groupActionReply': 'Відповісти',
        'groupActionReaction': 'Реакція',
        'groupActionCopy': 'Копіювати',
        'groupActionUnpin': 'Відкріпити',
        'groupActionPin': 'Закріпити',
        'groupActionEdit': 'Редагувати',
        'groupActionDeleteForAll': 'Видалити для всіх',
      },
      'en': {
        'groupActionSave': 'Save',
        'groupActionReply': 'Reply',
        'groupActionReaction': 'React',
        'groupActionCopy': 'Copy',
        'groupActionUnpin': 'Unpin',
        'groupActionPin': 'Pin',
        'groupActionEdit': 'Edit',
        'groupActionDeleteForAll': 'Delete for everyone',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }
    }

    await language.select('de');
    expect(language.text('groupActionReply'), 'Reply');
    expect(language.text('groupActionDeleteForAll'), 'Delete for everyone');

    await language.select('system');
  });
}
