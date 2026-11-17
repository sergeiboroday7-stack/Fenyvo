import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:spartan_chat_final/widgets/device_transfer_pairing_screen.dart';
import 'package:spartan_chat_final/services/crypto/old_device_pin.dart';
import 'package:spartan_chat_final/screens/new_device_transfer_screen.dart';

void main() {
  for (final language in ['ru', 'uk', 'en']) {
    testWidgets('old-device public pairing code renders ' + language, (
      tester,
    ) async {
      final pin = OldDevicePin.create(
        accountId: '11111111-1111-4111-8111-111111111111',
        username: 'Alice',
        publicKey: [5, ...List.filled(32, 7)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceTransferPairingScreen(
            loadPin: () async => pin,
            language: language,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(pin.username), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text(pin.encode()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('new-device invalid pin fails before network ' + language, (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NewDeviceTransferScreen(
            username: 'Alice',
            password: 'test',
            language: language,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
