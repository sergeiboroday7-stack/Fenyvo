import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/screens/auth_screen.dart';
import '../lib/services/app_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auth registration has a valid Material hierarchy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'logged_in': false});

    final language = AppLanguageService.instance;
    await language.initialize();
    await language.select('ru');

    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final back = find.byTooltip('Назад');

    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text('СОЗДАТЬ АККАУНТ'), findsOneWidget);

    await tester.tap(find.text('СОЗДАТЬ АККАУНТ'));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await language.select('system');
  });
}
