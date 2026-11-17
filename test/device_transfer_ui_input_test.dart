import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/old_device_pin.dart';
import 'package:spartan_chat_final/widgets/device_transfer_code_input.dart';
import 'package:spartan_chat_final/widgets/device_transfer_pairing_screen.dart';

void main() {
  String pin([String username = 'Alice']) => OldDevicePin.create(
    accountId: '11111111-1111-4111-8111-111111111111',
    username: username, publicKey: [5, ...List.filled(32, 7)],
  ).encode();

  Future<void> showInput(WidgetTester tester, TextEditingController controller,
      {TransferCodeScanner? scan, bool enabled = true}) => tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DeviceTransferCodeInput(controller: controller,
      username: 'Alice', language: 'ru', scanCode: scan, enabled: enabled)),
  ));

  testWidgets('valid scan fills code without submitting transfer', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var calls = 0;
    await showInput(tester, controller, scan: (_) async { calls++; return pin(); });
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    await tester.pumpAndSettle();
    expect(controller.text, pin());
    expect(calls, 1);
    expect(find.text('Нужен код переноса именно этого аккаунта со старого телефона.'), findsNothing);
  });

  for (final invalid in ['https://example.com', '{bad json', 'wrong-account', 'oversized']) {
    testWidgets('rejects $invalid without replacing previous code', (tester) async {
      final controller = TextEditingController(text: 'previous');
      addTearDown(controller.dispose);
      final raw = invalid == 'wrong-account' ? pin('Bob') : invalid == 'oversized' ? 'a' * 2049 : invalid;
      await showInput(tester, controller, scan: (_) async => raw);
      await tester.tap(find.byKey(const ValueKey('transfer-scan')));
      await tester.pumpAndSettle();
      expect(controller.text, 'previous');
      expect(find.text('Нужен код переноса именно этого аккаунта со старого телефона.'), findsOneWidget);
    });
  }

  testWidgets('cancelled scan preserves manual code', (tester) async {
    final controller = TextEditingController(text: 'previous');
    addTearDown(controller.dispose);
    await showInput(tester, controller, scan: (_) async => null);
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    await tester.pumpAndSettle();
    expect(controller.text, 'previous');
    expect(find.text('Нужен код переноса именно этого аккаунта со старого телефона.'), findsNothing);
  });

  testWidgets('pending scanner cannot open twice', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final result = Completer<String?>();
    var calls = 0;
    await showInput(tester, controller, scan: (_) { calls++; return result.future; });
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    expect(calls, 1);
    result.complete(pin());
    await tester.pumpAndSettle();
    expect(controller.text, pin());
  });

  testWidgets('late camera result cannot change disposed input', (tester) async {
    final controller = TextEditingController(text: 'previous');
    addTearDown(controller.dispose);
    final result = Completer<String?>();
    await showInput(tester, controller, scan: (_) => result.future);
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    result.complete(pin());
    await tester.pumpAndSettle();
    expect(controller.text, 'previous');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows keeps manual input without a camera button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await showInput(tester, controller);
      expect(find.byKey(const ValueKey('transfer-scan')), findsNothing);
      expect(find.byKey(const ValueKey('transfer-paste')), findsOneWidget);
      await tester.enterText(find.byType(TextField), pin());
      expect(controller.text, pin());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('paste validates matching account', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform, (call) async => call.method == 'Clipboard.getData' ? {'text': pin()} : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await showInput(tester, controller);
    await tester.tap(find.byKey(const ValueKey('transfer-paste')));
    await tester.pumpAndSettle();
    expect(controller.text, pin());
  });

  testWidgets('disabled input cannot scan or paste', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var calls = 0;
    await showInput(tester, controller, enabled: false, scan: (_) async { calls++; return pin(); });
    await tester.tap(find.byKey(const ValueKey('transfer-scan')));
    expect(calls, 0);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('transfer-paste'))).onPressed, isNull);
  });

  testWidgets('transfer language follows system locale', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('uk');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    expect(transferText('system', 'русский', 'українська', 'English'), 'українська');
    expect(transferText('ru', 'русский', 'українська', 'English'), 'русский');
  });
}
