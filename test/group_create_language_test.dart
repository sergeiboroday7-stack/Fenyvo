import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group creation strings in RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'groupCreateTitle': 'Новая группа',
        'groupCreateSubmit': 'Создать группу',
      },
      'uk': {
        'groupCreateTitle': 'Нова група',
        'groupCreateSubmit': 'Створити групу',
      },
      'en': {
        'groupCreateTitle': 'New group',
        'groupCreateSubmit': 'Create group',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      for (final key in [
        'groupCreateName',
        'groupCreateParticipants',
        'groupCreateNoUsers',
        'groupCreateSaving',
        'groupCreateFailed',
        'groupCreateEnterName',
        'groupCreateSelectMember',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }

      expect(
        language.text('groupCreateSelected').replaceAll('{count}', '3'),
        contains('3'),
      );
    }

    await language.select('de');
    expect(language.text('groupCreateTitle'), 'New group');
    expect(language.text('groupCreateSubmit'), 'Create group');

    await language.select('system');
  });
}
