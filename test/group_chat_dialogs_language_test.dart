import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group message dialogs RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupDialogEditTitle': 'Редактировать сообщение',
        'groupDialogCancel': 'Отмена',
        'groupDialogDeleteTitle': 'Удалить сообщение?',
        'groupDialogDeleteWarning':
            'Сообщение исчезнет у всех участников группы.',
        'groupActionSave': 'Сохранить',
        'groupActionDeleteForAll': 'Удалить у всех',
      },
      'uk': {
        'groupDialogEditTitle': 'Редагувати повідомлення',
        'groupDialogCancel': 'Скасувати',
        'groupDialogDeleteTitle': 'Видалити повідомлення?',
        'groupDialogDeleteWarning':
            'Повідомлення зникне в усіх учасників групи.',
        'groupActionSave': 'Зберегти',
        'groupActionDeleteForAll': 'Видалити для всіх',
      },
      'en': {
        'groupDialogEditTitle': 'Edit message',
        'groupDialogCancel': 'Cancel',
        'groupDialogDeleteTitle': 'Delete message?',
        'groupDialogDeleteWarning':
            'The message will disappear for everyone in the group.',
        'groupActionSave': 'Save',
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
    expect(language.text('groupDialogCancel'), 'Cancel');
    expect(language.text('groupDialogDeleteTitle'), 'Delete message?');

    await language.select('system');
  });
}
