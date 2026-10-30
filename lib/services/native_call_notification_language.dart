import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

import 'app_language_service.dart';

/// User-facing native call notification text.
///
/// Protocol identifiers, call IDs, payloads and channel IDs are not translated.
class NativeCallNotificationLanguage {
  const NativeCallNotificationLanguage._();

  static String get currentCode {
    final selected = AppLanguageService.instance.code.value;
    return selected == 'system'
        ? PlatformDispatcher.instance.locale.languageCode
        : selected;
  }

  /// Reads the selected language from persistent settings.
  ///
  /// This is suitable for the Firebase background message isolate:
  /// it does not depend on the main isolate's ValueNotifier state.
  static Future<String> savedCode() async {
    final preferences = await SharedPreferences.getInstance();

    // Refresh the legacy SharedPreferences cache before reading.
    await preferences.reload();

    final selected = preferences.getString('app_language_code') ?? 'system';

    return selected == 'system'
        ? PlatformDispatcher.instance.locale.languageCode
        : selected;
  }

  static String text(String key) => forCode(key, currentCode);

  static String forCode(String key, String code) {
    final translations = _translations[key];

    if (translations == null) return key;

    return switch (code) {
      'ru' => translations[0],
      'uk' => translations[1],
      _ => translations[2],
    };
  }

  static const Map<String, List<String>> _translations = {
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
}
