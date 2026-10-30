import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group attachments translations RU UK EN and fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const expected = <String, List<String>>{
      'ru': ['Скачать', 'Сохранить', 'Вложение', 'Эмодзи'],
      'uk': ['Завантажити', 'Зберегти', 'Вкладення', 'Емодзі'],
      'en': ['Download', 'Save', 'Attachment', 'Emoji'],
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      expect(language.text('groupAttachmentDownload'), expected[code]![0]);
      expect(language.text('groupAttachmentSave'), expected[code]![1]);
      expect(language.text('groupAttachmentAdd'), expected[code]![2]);
      expect(language.text('groupAttachmentEmoji'), expected[code]![3]);

      for (final key in [
        'groupAttachmentPhotoPickFailed',
        'groupAttachmentVideoPickFailed',
        'groupAttachmentFilePickFailed',
        'groupAttachmentSendFailed',
        'groupAttachmentSaveFailed',
      ]) {
        final value = language.text(key).replaceAll('{error}', 'TEST_ERROR');
        expect(value, contains('TEST_ERROR'));
        expect(value, isNot(contains('{error}')));
      }

      final saved = language
          .text('groupAttachmentSaved')
          .replaceAll('{path}', 'TEST_PATH');
      expect(saved, contains('TEST_PATH'));

      for (final key in [
        'groupAttachmentPathMissing',
        'groupAttachmentCorrupted',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }
    }

    await language.select('de');
    expect(language.text('groupAttachmentDownload'), 'Download');
    expect(language.text('groupAttachmentEmoji'), 'Emoji');

    await language.select('system');
  });
}
