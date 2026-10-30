import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Recovery status and errors follow selected language', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'recoveryErrorInvalidResponse': 'Некорректный ответ сервера.',
        'recoveryErrorInvalidChallenge': 'Некорректное подтверждение сервера.',
        'recoveryErrorGeneric': 'Не удалось восстановить доступ.',
        'recoveryErrorDisconnected': 'Нет соединения с сервером.',
        'recoveryErrorSigningFailed':
            'Не удалось создать подтверждение из секретных слов.',
        'recoveryStatusRequesting': 'Запрашиваем подтверждение...',
        'recoveryErrorTimeout': 'Сервер не ответил. Попробуйте снова.',
        'recoveryErrorConnectionFailed': 'Не удалось подключиться к серверу.',
      },
      'uk': {
        'recoveryErrorInvalidResponse': 'Некоректна відповідь сервера.',
        'recoveryErrorInvalidChallenge': 'Некоректне підтвердження сервера.',
        'recoveryErrorGeneric': 'Не вдалося відновити доступ.',
        'recoveryErrorDisconnected': 'Немає з’єднання із сервером.',
        'recoveryErrorSigningFailed':
            'Не вдалося створити підтвердження із секретних слів.',
        'recoveryStatusRequesting': 'Запитуємо підтвердження...',
        'recoveryErrorTimeout': 'Сервер не відповів. Спробуйте ще раз.',
        'recoveryErrorConnectionFailed': 'Не вдалося підключитися до сервера.',
      },
      'en': {
        'recoveryErrorInvalidResponse': 'Invalid server response.',
        'recoveryErrorInvalidChallenge': 'Invalid server challenge.',
        'recoveryErrorGeneric': 'Could not recover the account.',
        'recoveryErrorDisconnected': 'No connection to the server.',
        'recoveryErrorSigningFailed':
            'Could not create proof from the secret words.',
        'recoveryStatusRequesting': 'Requesting verification...',
        'recoveryErrorTimeout': 'The server did not respond. Please try again.',
        'recoveryErrorConnectionFailed': 'Could not connect to the server.',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);
      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }
    }

    await language.select('de');
    expect(
      language.text('recoveryErrorDisconnected'),
      'No connection to the server.',
    );

    await language.select('system');
  });
}
