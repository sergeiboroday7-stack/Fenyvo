import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/device_transfer_request.dart';
import 'package:spartan_chat_final/widgets/device_transfer_approval_panel.dart';

DeviceTransferRequest request() {
  final now = DateTime.now().millisecondsSinceEpoch,
      key = [5, ...List<int>.filled(32, 9)];
  return DeviceTransferRequest.parse(
    {
      'purpose': 'fenyvo-device-transfer-v1',
      'accountId': '11111111-1111-4111-8111-111111111111',
      'username': 'Alice',
      'newIdentityKey': base64Encode(key),
      'candidateHash': sha256.convert(key).toString(),
      'nonce': 'b' * 64,
      'issuedAt': now - 1,
      'expiresAt': now + 120000,
    },
    accountId: '11111111-1111-4111-8111-111111111111',
    username: 'Alice',
    nowMs: now,
  )!;
}

void main() {
  for (final language in ['ru', 'uk', 'en']) {
    testWidgets('requires comparison and explicit approval ' + language, (
      tester,
    ) async {
      var signed = 0, rejected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DeviceTransferApprovalPanel(
                request: request(),
                language: language,
                onApprove: () async {
                  signed++;
                  return false;
                },
                onReject: () {
                  rejected++;
                },
              ),
            ),
          ),
        ),
      );
      expect(signed, 0);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(signed, 0);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(signed, 1);
      await tester.ensureVisible(find.byType(TextButton));
      await tester.tap(find.byType(TextButton));
      expect(rejected, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
