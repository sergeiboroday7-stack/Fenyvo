import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/widgets/device_transfer_pairing_screen.dart';

void main() {
  for (final code in ['ru', 'uk', 'en']) {
    testWidgets('system language resolves to $code', (tester) async {
      tester.platformDispatcher.localeTestValue = Locale(code);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      expect(transferText('system', 'RU', 'UK', 'EN'), code.toUpperCase());
      expect(transferText('ru', 'RU', 'UK', 'EN'), 'RU');
    });
  }
}
