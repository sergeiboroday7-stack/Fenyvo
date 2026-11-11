import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/widgets/private_translation_sheet.dart')
      .readAsStringSync();

  test('contains RU UK and EN dictionaries', () {
    for (final code in ['ru', 'uk', 'en']) {
      expect(source.contains("'$code': {"), isTrue);
    }
  });

  test('all nine UI keys exist for each language', () {
    for (final key in [
      'title',
      'original',
      'translateTo',
      'loading',
      'translate',
      'result',
      'copied',
      'copy',
      'error',
    ]) {
      expect(RegExp("'$key':").allMatches(source).length, 3);
    }
  });

  test('respects individual language and system language', () {
    expect(source.contains('AppLanguageService.instance.code.value'), isTrue);
    expect(source.contains('platformDispatcher.locale.languageCode'), isTrue);
    expect(source.contains("values['en']!"), isTrue);
  });

  test('keeps both E2EE guards and translation callback', () {
    expect(
      RegExp(r'PrivateExternalTextPolicy\.canSendMessage\s*\(')
          .allMatches(source)
          .length,
      2,
    );
    expect(source.contains('_requestTranslation('), isTrue);
  });
}
