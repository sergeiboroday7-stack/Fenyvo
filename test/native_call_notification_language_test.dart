import 'package:fenyvo/services/native_call_notification_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const expected = <String, List<String>>{
    'incomingVideoOpen': [
      'Входящий видеозвонок — открыть FENYVO',
      'Вхідний відеодзвінок — відкрити FENYVO',
      'Incoming video call — open FENYVO',
    ],
    'incomingAudioOpen': [
      'Входящий аудиозвонок — открыть FENYVO',
      'Вхідний аудіодзвінок — відкрити FENYVO',
      'Incoming voice call — open FENYVO',
    ],
    'missedVideo': [
      'Пропущенный видеозвонок',
      'Пропущений відеодзвінок',
      'Missed video call',
    ],
    'missedAudio': ['Пропущенный звонок', 'Пропущений дзвінок', 'Missed call'],
    'incomingVideo': ['Видеозвонок', 'Відеодзвінок', 'Video call'],
    'incomingAudio': ['Аудиозвонок', 'Аудіодзвінок', 'Voice call'],
    'accept': ['Принять', 'Прийняти', 'Accept'],
    'decline': ['Отклонить', 'Відхилити', 'Decline'],
    'endCall': ['Завершить', 'Завершити', 'End call'],
    'callFenyvo': ['Звонок FENYVO', 'Дзвінок FENYVO', 'FENYVO call'],
    'callsChannel': ['Звонки FENYVO', 'Дзвінки FENYVO', 'FENYVO calls'],
    'missedCallsChannel': [
      'Пропущенные звонки',
      'Пропущені дзвінки',
      'Missed calls',
    ],
    'contact': ['Собеседник', 'Співрозмовник', 'Contact'],
  };

  test('background reader loads saved Ukrainian selection', () async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'uk'});

    expect(await NativeCallNotificationLanguage.savedCode(), 'uk');
    expect(
      NativeCallNotificationLanguage.forCode(
        'accept',
        await NativeCallNotificationLanguage.savedCode(),
      ),
      'Прийняти',
    );
  });

  test('background reader loads saved English selection', () async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});

    expect(await NativeCallNotificationLanguage.savedCode(), 'en');
    expect(
      NativeCallNotificationLanguage.forCode(
        'missedAudio',
        await NativeCallNotificationLanguage.savedCode(),
      ),
      'Missed call',
    );
  });
  for (final entry in expected.entries) {
    test('${entry.key} translates into ru / uk / en', () {
      expect(
        NativeCallNotificationLanguage.forCode(entry.key, 'ru'),
        entry.value[0],
      );
      expect(
        NativeCallNotificationLanguage.forCode(entry.key, 'uk'),
        entry.value[1],
      );
      expect(
        NativeCallNotificationLanguage.forCode(entry.key, 'en'),
        entry.value[2],
      );
    });
  }

  test('unsupported language uses English fallback', () {
    expect(
      NativeCallNotificationLanguage.forCode('missedAudio', 'de'),
      'Missed call',
    );
  });

  test('unknown key is preserved', () {
    expect(
      NativeCallNotificationLanguage.forCode('unknown_key', 'uk'),
      'unknown_key',
    );
  });
}
