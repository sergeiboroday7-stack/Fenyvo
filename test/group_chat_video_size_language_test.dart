import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group video, connection and size units RU UK EN', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, Map<String, String>>{
      'ru': {
        'groupInlineVideoOpenFailed': 'Видео не удалось открыть',
        'groupInlineVideoSave': 'Сохранить видео',
        'groupSizeBytes': 'Б',
        'groupSizeKilobytes': 'КБ',
        'groupSizeMegabytes': 'МБ',
        'groupChatErrorFallback': 'Ошибка группового чата',
      },
      'uk': {
        'groupInlineVideoOpenFailed': 'Не вдалося відкрити відео',
        'groupInlineVideoSave': 'Зберегти відео',
        'groupSizeBytes': 'Б',
        'groupSizeKilobytes': 'КБ',
        'groupSizeMegabytes': 'МБ',
        'groupChatErrorFallback': 'Помилка групового чату',
      },
      'en': {
        'groupInlineVideoOpenFailed': 'Could not open video',
        'groupInlineVideoSave': 'Save video',
        'groupSizeBytes': 'B',
        'groupSizeKilobytes': 'KB',
        'groupSizeMegabytes': 'MB',
        'groupChatErrorFallback': 'Group chat error',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in expected[code]!.entries) {
        expect(language.text(entry.key), entry.value);
      }

      for (final key in [
        'noServerConnection',
        'photoDamaged',
        'groupChatVideoUnavailable',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }
    }

    await language.select('de');

    expect(language.text('groupInlineVideoSave'), 'Save video');
    expect(language.text('groupSizeBytes'), 'B');
    expect(language.text('groupSizeKilobytes'), 'KB');
    expect(language.text('groupSizeMegabytes'), 'MB');
    expect(language.text('groupChatErrorFallback'), 'Group chat error');

    await language.select('system');
  });
}
