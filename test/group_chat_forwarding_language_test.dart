import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group chat forwarding labels RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    final expected = <String, Map<String, String>>{
      'ru': {
        'groupForwardSuccess': 'Сообщение переслано',
        'groupForwardSend': 'Отправить',
      },
      'uk': {
        'groupForwardSuccess': 'Повідомлення переслано',
        'groupForwardSend': 'Надіслати',
      },
      'en': {
        'groupForwardSuccess': 'Message forwarded',
        'groupForwardSend': 'Send',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      final keys = ['groupForwardNoChats', 'groupForwardSelectRecipient'];

      for (final key in keys) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }

      expect(
        language.text('groupForwardFailed').replaceAll('{error}', 'TEST_ERROR'),
        contains('TEST_ERROR'),
      );

      expect(
        language.text('groupForwardRecipientsCount').replaceAll('{count}', '3'),
        contains('3'),
      );

      expect(
        language.text('groupForwardSendCount').replaceAll('{count}', '2'),
        contains('2'),
      );
    }

    await language.select('de');
    expect(language.text('groupForwardSend'), 'Send');
    expect(language.text('groupForwardSuccess'), 'Message forwarded');

    await language.select('system');
  });
}
