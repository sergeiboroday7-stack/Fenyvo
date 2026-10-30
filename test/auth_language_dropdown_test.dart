import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/screens/auth_screen.dart';
import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dropdown changes language and preserves entered data', (
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

    final back = find.byTooltip(language.text('authBack'));
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final create = find.text(language.text('authCreateAccount'));
    expect(create, findsOneWidget);

    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final dropdown = find.byType(DropdownButtonFormField<String>);
    expect(dropdown, findsOneWidget);

    var fields = find.byType(TextField);

    await tester.enterText(fields.at(0), 'dropdown_test_user');
    await tester.enterText(fields.at(1), 'example_test_123');
    await tester.pump();

    // Remove focus so the blinking cursor cannot affect settling.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    for (final choice in [
      (code: 'uk', label: 'Українська'),
      (code: 'en', label: 'English'),
      (code: 'ru', label: 'Русский'),
    ]) {
      await tester.ensureVisible(dropdown);
      await tester.pump();

      await tester.tap(dropdown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final option = find.textContaining(choice.label).last;
      expect(option, findsOneWidget);

      await tester.tap(option);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(language.code.value, choice.code);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_language_code'), choice.code);

      final state = tester.state<FormFieldState<String>>(dropdown);
      expect(state.value, choice.code);

      fields = find.byType(TextField);

      expect(
        tester.widget<TextField>(fields.at(0)).decoration!.hintText,
        language.text('authUsername'),
      );

      expect(
        tester.widget<TextField>(fields.at(1)).decoration!.hintText,
        language.text('authPassword'),
      );

      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        'dropdown_test_user',
      );

      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        'example_test_123',
      );

      expect(tester.takeException(), isNull);

      print('PASS: ${choice.code} selected, persisted, data preserved');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await language.select('system');
  });
}
