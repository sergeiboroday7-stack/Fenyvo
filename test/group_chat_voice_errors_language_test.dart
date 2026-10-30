import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group voice errors RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupVoiceRecordFailed': 'Не удалось начать запись: {error}',
        'groupVoiceSendFailed': 'Не удалось отправить голосовое: {error}',
        'groupVoiceCorrupted': 'Голосовое сообщение повреждено',
        'groupVoiceUnavailable': 'Голосовое сообщение недоступно',
        'groupVoicePlaybackFailed':
            'Не удалось воспроизвести голосовое: {error}',
      },
      'uk': {
        'groupVoiceRecordFailed': 'Не вдалося почати запис: {error}',
        'groupVoiceSendFailed':
            'Не вдалося надіслати голосове повідомлення: {error}',
        'groupVoiceCorrupted': 'Голосове повідомлення пошкоджено',
        'groupVoiceUnavailable': 'Голосове повідомлення недоступне',
        'groupVoicePlaybackFailed':
            'Не вдалося відтворити голосове повідомлення: {error}',
      },
      'en': {
        'groupVoiceRecordFailed': 'Could not start recording: {error}',
        'groupVoiceSendFailed': 'Could not send voice message: {error}',
        'groupVoiceCorrupted': 'Voice message is corrupted',
        'groupVoiceUnavailable': 'Voice message is unavailable',
        'groupVoicePlaybackFailed': 'Could not play voice message: {error}',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      for (final key in [
        'groupVoiceRecordFailed',
        'groupVoiceSendFailed',
        'groupVoicePlaybackFailed',
      ]) {
        final displayed = language
            .text(key)
            .replaceAll('{error}', 'TEST_ERROR');

        expect(displayed, contains('TEST_ERROR'));
        expect(displayed, isNot(contains('{error}')));
      }
    }

    await language.select('de');
    expect(language.text('groupVoiceCorrupted'), 'Voice message is corrupted');

    expect(
      language
          .text('groupVoicePlaybackFailed')
          .replaceAll('{error}', 'TEST_ERROR'),
      'Could not play voice message: TEST_ERROR',
    );

    await language.select('system');
  });
}
