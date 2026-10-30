import 'package:fenyvo/services/app_language_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final language = AppLanguageService.instance;
  late String previousCode;

  setUp(() {
    previousCode = language.code.value;
  });

  tearDown(() {
    language.code.value = previousCode;
  });

  test('Ukrainian: host ended the broadcast', () {
    language.code.value = 'uk';

    expect(language.text('groupCallHostEndedBroadcast'), 'Автор завершив ефір');
  });

  test('Russian: host ended the broadcast', () {
    language.code.value = 'ru';

    expect(language.text('groupCallHostEndedBroadcast'), 'Автор завершил эфир');
  });

  test('English: host ended the broadcast', () {
    language.code.value = 'en';

    expect(
      language.text('groupCallHostEndedBroadcast'),
      'The host ended the broadcast',
    );
  });
}
