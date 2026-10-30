import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final language = AppLanguageService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await language.initialize();
  });

  test(
    'Russian, Ukrainian and English translations switch correctly',
    () async {
      await language.select('ru');
      expect(language.code.value, 'ru');
      expect(language.text('authCreateAccount'), 'СОЗДАТЬ АККАУНТ');
      expect(language.text('authUsername'), 'Ник пользователя');

      await language.select('uk');
      expect(language.code.value, 'uk');
      expect(language.locale, const Locale('uk'));
      expect(language.text('authCreateAccount'), 'СТВОРИТИ ОБЛІКОВИЙ ЗАПИС');
      expect(language.text('authUsername'), 'Нік користувача');
      expect(language.text('authForgotPassword'), 'Забули пароль?');

      await language.select('en');
      expect(language.code.value, 'en');
      expect(language.text('authCreateAccount'), 'CREATE ACCOUNT');
      expect(language.text('authUsername'), 'Username');
    },
  );

  test('Language choice is persisted and restored', () async {
    await language.select('uk');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_language_code'), 'uk');

    language.code.value = 'ru';
    await language.initialize();

    expect(language.code.value, 'uk');
    expect(language.text('authUsername'), 'Нік користувача');
  });

  test('Device language mode leaves MaterialApp locale unresolved', () async {
    await language.select('uk');
    await language.select('system');

    expect(language.code.value, 'system');
    expect(language.locale, isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_language_code'), 'system');
  });

  test('Missing new German translation falls back to English', () async {
    await language.select('de');

    expect(language.text('authUsername'), 'Username');
    expect(language.text('authCreateAccount'), 'CREATE ACCOUNT');

    // Existing German translations must remain available.
    expect(language.text('create'), 'KONTO ERSTELLEN');
  });

  test('Unknown language codes do not change the selection', () async {
    await language.select('uk');
    await language.select('unsupported-language');

    expect(language.code.value, 'uk');
  });
}
