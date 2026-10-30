import 'package:flutter/widgets.dart';

import 'app_language_service.dart';

/// UI translations for private voice and video calls.
/// Never used for protocol identifiers or signaling payloads.
class PrivateCallLanguage {
  const PrivateCallLanguage._();

  static String get currentCode {
    final selected = AppLanguageService.instance.code.value;
    return selected == 'system'
        ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
        : selected;
  }

  static String text(String russian) {
    final translations = _translations[russian];

    if (translations == null) {
      return russian;
    }

    return switch (currentCode) {
      'ru' => russian,
      'uk' => translations[0],
      _ => translations[1],
    };
  }

  static const Map<String, List<String>> _translations = {
    'Собеседник': ['Співрозмовник', 'Contact'],
    'Звонок завершён': ['Дзвінок завершено', 'Call ended'],
    'Вызов отклонён': ['Виклик відхилено', 'Call declined'],
    'Пользователь занят': ['Користувач зайнятий', 'User is busy'],
    'Пользователь не в сети': ['Користувач не в мережі', 'User is offline'],
    'Не удалось начать звонок': [
      'Не вдалося розпочати дзвінок',
      'Could not start call',
    ],
    'Ваше видео. Перетащите или нажмите, чтобы увеличить.': [
      'Ваше відео. Перетягніть або натисніть, щоб збільшити.',
      'Your video. Drag or tap to enlarge.',
    ],
    'Видео собеседника. Перетащите или нажмите, чтобы увеличить.': [
      'Відео співрозмовника. Перетягніть або натисніть, щоб збільшити.',
      'Contact video. Drag or tap to enlarge.',
    ],
    'Камера\nвыключена': ['Камеру\nвимкнено', 'Camera\noff'],
    'Защищённый звонок': ['Захищений дзвінок', 'Secure call'],
    'Отклонить': ['Відхилити', 'Decline'],
    'Отклонить звонок': ['Відхилити дзвінок', 'Decline call'],
    'Принять': ['Прийняти', 'Accept'],
    'Принять видеозвонок': ['Прийняти відеодзвінок', 'Accept video call'],
    'Принять аудиозвонок': ['Прийняти аудіодзвінок', 'Accept voice call'],
    'Аватар: ': ['Аватар: ', 'Avatar: '],
    'Ожидание ответа…': ['Очікування відповіді…', 'Waiting for an answer…'],
    'Видеозвонок…': ['Відеодзвінок…', 'Video call…'],
    'Аудиозвонок…': ['Аудіодзвінок…', 'Voice call…'],
    'Нет ответа': ['Немає відповіді', 'No answer'],
    'Подключение…': ['Підключення…', 'Connecting…'],
    'Соединение…': ['З’єднання…', 'Connecting…'],
    'Соединено': ['З’єднано', 'Connected'],
    'Входящий видеозвонок': ['Вхідний відеодзвінок', 'Incoming video call'],
    'Входящий аудиозвонок': ['Вхідний аудіодзвінок', 'Incoming voice call'],
    'Восстановление связи с сервером…': [
      'Відновлення зв’язку із сервером…',
      'Restoring server connection…',
    ],
    'Восстановление соединения…': ['Відновлення з’єднання…', 'Reconnecting…'],
    'Восстанавливаем связь…': ['Відновлюємо зв’язок…', 'Reconnecting…'],
    'Слабое соединение': ['Слабке з’єднання', 'Poor connection'],
    'Соединение потеряно': ['З’єднання втрачено', 'Connection lost'],
    'Соединение завершено': ['З’єднання завершено', 'Connection ended'],
    'Не удалось установить соединение': [
      'Не вдалося встановити з’єднання',
      'Could not establish connection',
    ],
    'Не удалось переключить динамик': [
      'Не вдалося перемкнути динамік',
      'Could not switch speaker',
    ],
    'Не удалось переключить камеру': [
      'Не вдалося перемкнути камеру',
      'Could not switch camera',
    ],
    'Пропущенный звонок': ['Пропущений дзвінок', 'Missed call'],
    'Потеряна связь с сервером': [
      'Втрачено зв’язок із сервером',
      'Server connection lost',
    ],
    'Ошибка звонка': ['Помилка дзвінка', 'Call error'],
    'Разрешите доступ к камере и микрофону': [
      'Надайте доступ до камери та мікрофона',
      'Allow access to camera and microphone',
    ],
    'Разрешите доступ к микрофону': [
      'Надайте доступ до мікрофона',
      'Allow access to microphone',
    ],
    'Громкая связь': ['Гучний зв’язок', 'Speakerphone'],
    'Включена': ['Увімкнена', 'On'],
    'Выключена': ['Вимкнена', 'Off'],
    'Включён': ['Увімкнений', 'On'],
    'Выключен': ['Вимкнений', 'Off'],
    'Выключить громкую связь': [
      'Вимкнути гучний зв’язок',
      'Turn speakerphone off',
    ],
    'Включить громкую связь': [
      'Увімкнути гучний зв’язок',
      'Turn speakerphone on',
    ],
    'Микрофон': ['Мікрофон', 'Microphone'],
    'Выключить микрофон': ['Вимкнути мікрофон', 'Mute microphone'],
    'Включить микрофон': ['Увімкнути мікрофон', 'Unmute microphone'],
    'Камера': ['Камера', 'Camera'],
    'Выключить камеру': ['Вимкнути камеру', 'Turn camera off'],
    'Включить камеру': ['Увімкнути камеру', 'Turn camera on'],
    'Сменить\nкамеру': ['Змінити\nкамеру', 'Switch\ncamera'],
    'Переключить на другую камеру': [
      'Перемкнути на іншу камеру',
      'Switch to another camera',
    ],
    'Завершить': ['Завершити', 'End call'],
    'Завершить звонок': ['Завершити дзвінок', 'End the call'],
  };
}
