import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group add members translations RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});

    final language = AppLanguageService.instance;
    await language.initialize();

    final titles = <String, String>{
      'ru': 'Добавить участников',
      'uk': 'Додати учасників',
      'en': 'Add members',
    };

    for (final entry in titles.entries) {
      await language.select(entry.key);

      expect(language.text('groupAddTitle'), entry.value);

      for (final key in [
        'groupAddNewMembers',
        'groupAddNoAvailableUsers',
        'groupAddSaving',
        'groupAddSelectMembers',
        'groupAddFailed',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }

      expect(
        language.text('groupAddSelected').replaceAll('{count}', '2'),
        contains('2'),
      );

      expect(
        language.text('groupAddCount').replaceAll('{count}', '2'),
        contains('2'),
      );
    }

    await language.select('de');
    expect(language.text('groupAddTitle'), 'Add members');

    await language.select('system');
  });
}
