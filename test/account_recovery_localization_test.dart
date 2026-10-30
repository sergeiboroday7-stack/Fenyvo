import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/screens/account_recovery_screen.dart';
import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Recovery screen translates without clearing username', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();
    await language.select('ru');

    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AccountRecoveryScreen()));
    await tester.pump();

    expect(find.text('Восстановление доступа'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.byType(TextField).first, 'test_recovery_ui');
    await tester.pump();

    for (final code in ['uk', 'en', 'ru']) {
      await language.select(code);
      await tester.pump();

      expect(find.text(language.text('recoveryScreenTitle')), findsOneWidget);
      expect(
        find.text(language.text('recoveryScreenDescription')),
        findsOneWidget,
      );
      expect(find.text(language.text('recoveryScreenSubmit')), findsOneWidget);

      for (final entry in [
        (0, 'recoveryScreenUsername'),
        (1, 'recoveryScreenWords'),
        (2, 'recoveryScreenNewPassword'),
        (3, 'recoveryScreenConfirmPassword'),
      ]) {
        final field = tester.widget<TextField>(
          find.byType(TextField).at(entry.$1),
        );
        expect(field.decoration!.labelText, language.text(entry.$2));
      }

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'test_recovery_ui',
      );
      expect(tester.takeException(), isNull);
      print('PASS: $code recovery interface translated');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await language.select('system');
  });

  test('Unsupported recovery translation falls back to English', () async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageService.instance;
    await language.initialize();
    await language.select('de');
    expect(language.text('recoveryScreenTitle'), 'Account recovery');
    expect(language.text('recoveryScreenSubmit'), 'Reset password');
    await language.select('system');
  });
}
