import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group voice UI RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupVoiceStopAndSend': 'Остановить и отправить',
        'groupVoicePlay': 'Воспроизвести',
        'groupVoiceStop': 'Стоп',
        'groupVoiceFinishRecordingFirst':
            'Сначала завершите запись голосового сообщения',
        'groupVoiceMicrophoneDenied': 'Нет разрешения на микрофон',
      },
      'uk': {
        'groupVoiceStopAndSend': 'Зупинити й надіслати',
        'groupVoicePlay': 'Відтворити',
        'groupVoiceStop': 'Зупинити',
        'groupVoiceFinishRecordingFirst':
            'Спочатку завершіть запис голосового повідомлення',
        'groupVoiceMicrophoneDenied': 'Немає дозволу на використання мікрофона',
      },
      'en': {
        'groupVoiceStopAndSend': 'Stop and send',
        'groupVoicePlay': 'Play',
        'groupVoiceStop': 'Stop',
        'groupVoiceFinishRecordingFirst':
            'Finish recording the voice message first',
        'groupVoiceMicrophoneDenied': 'Microphone permission is required',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      for (final key in ['groupCallVoiceMessage', 'groupCallSendMessage']) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }
    }

    await language.select('de');
    expect(language.text('groupVoicePlay'), 'Play');
    expect(language.text('groupVoiceStopAndSend'), 'Stop and send');

    await language.select('system');
  });
}
