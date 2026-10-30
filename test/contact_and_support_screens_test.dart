import 'package:fenyvo/services/app_language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/screens/my_contact_screen.dart';
import 'package:fenyvo/screens/support_ai_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLanguageService.instance.code.value = 'ru';
  testWidgets('my contact screen shows username and sharing actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MyContactScreen(username: 'SpartaFenix')),
    );

    expect(find.text('@SpartaFenix'), findsOneWidget);
    expect(find.text('Поделиться контактом'), findsOneWidget);
    expect(find.text('Копировать ссылку'), findsOneWidget);
  });

  testWidgets('support assistant discloses AI and protects secret data', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SupportAiScreen()));

    expect(find.text('Помощник поддержки'), findsOneWidget);
    expect(
      find.textContaining('автоматический помощник поддержки Fenyvo'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Личные чаты автоматически не читаются'),
      findsOneWidget,
    );
    expect(find.text('Опишите вопрос без секретных данных'), findsOneWidget);
  });
}
