import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/screens/auth_screen.dart';
import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Registration language changes preserve entered fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'logged_in': false});

    final language = AppLanguageService.instance;
    await language.initialize();
    await language.select('ru');

    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // A login form may appear before the welcome screen.
    final back = find.byTooltip(language.text('authBack'));
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final createLabel = language.text('authCreateAccount');
    expect(find.text(createLabel), findsOneWidget);

    await tester.tap(find.text(createLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    final inputFields = find.byType(TextField);
    expect(inputFields.evaluate().length, greaterThanOrEqualTo(2));

    final username = tester.widget<TextField>(inputFields.at(0)).controller!;
    final password = tester.widget<TextField>(inputFields.at(1)).controller!;

    await tester.enterText(inputFields.at(0), 'locale_test_user');
    await tester.enterText(inputFields.at(1), 'example_test_123');
    await tester.pump();

    expect(username.text, 'locale_test_user');
    expect(password.text, 'example_test_123');

    for (final code in ['uk', 'en', 'ru']) {
      await language.select(code);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final fields = find.byType(TextField);

      expect(
        tester.widget<TextField>(fields.at(0)).decoration!.hintText,
        language.text('authUsername'),
      );

      expect(
        tester.widget<TextField>(fields.at(1)).decoration!.hintText,
        language.text('authPassword'),
      );

      expect(username.text, 'locale_test_user');
      expect(password.text, 'example_test_123');

      expect(tester.takeException(), isNull);

      print('PASS: $code labels changed; entered text preserved');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await language.select('system');
  });
}
