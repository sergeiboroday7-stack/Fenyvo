import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/app_language_service.dart';

String memberLabel(AppLanguageService language, int count) {
  final lastTwo = count % 100;
  final lastDigit = count % 10;
  final key = language.text('groupStatusMemberOne') == 'member'
      ? (count == 1 ? 'groupStatusMemberOne' : 'groupStatusMemberMany')
      : lastTwo >= 11 && lastTwo <= 14
      ? 'groupStatusMemberMany'
      : lastDigit == 1
      ? 'groupStatusMemberOne'
      : lastDigit >= 2 && lastDigit <= 4
      ? 'groupStatusMemberFew'
      : 'groupStatusMemberMany';

  return '$count ${language.text(key)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Group status translations and numeric forms', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();

    const counts = <String, Map<int, String>>{
      'ru': {
        1: '1 участник',
        2: '2 участника',
        5: '5 участников',
        11: '11 участников',
        21: '21 участник',
        22: '22 участника',
        114: '114 участников',
      },
      'uk': {
        1: '1 учасник',
        2: '2 учасники',
        5: '5 учасників',
        11: '11 учасників',
        21: '21 учасник',
        22: '22 учасники',
        114: '114 учасників',
      },
      'en': {
        1: '1 member',
        2: '2 members',
        5: '5 members',
        11: '11 members',
        21: '21 members',
        22: '22 members',
        101: '101 members',
        121: '121 members',
        114: '114 members',
      },
    };

    for (final code in ['ru', 'uk', 'en']) {
      await language.select(code);

      for (final entry in counts[code]!.entries) {
        expect(memberLabel(language, entry.key), entry.value);
      }

      final one = language
          .text('groupStatusTypingOne')
          .replaceAll('{user}', 'UserA');
      final two = language
          .text('groupStatusTypingTwo')
          .replaceAll('{first}', 'UserA')
          .replaceAll('{second}', 'UserB');
      final many = language
          .text('groupStatusTypingMany')
          .replaceAll('{count}', '4');

      expect(one, contains('UserA'));
      expect(two, contains('UserA'));
      expect(two, contains('UserB'));
      expect(many, contains('4'));

      for (final key in [
        'groupStatusToday',
        'groupStatusYesterday',
        'groupStatusCreator',
      ]) {
        expect(language.text(key), isNotEmpty);
        expect(language.text(key), isNot(key));
      }
    }

    await language.select('de');
    expect(memberLabel(language, 2), '2 members');
    expect(language.text('groupStatusToday'), 'Today');

    await language.select('system');
  });
}
