import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/device_transfer_diagnostics.dart';
import 'package:fenyvo/widgets/device_transfer_failure_panel.dart';

void main() {
  test('known local identity guard is distinguished from unknown local errors', () {
    final profile = classifyTransferFailure(StateError('Existing local profile identity is protected'), TransferDiagnosticStage.localProfile);
    expect(profile.code, TransferFailureCode.existingProfile);
    final other = classifyTransferFailure(StateError('PRIVATE_CANARY'), TransferDiagnosticStage.localProfile);
    expect(other.code, TransferFailureCode.localPreparation);
    expect(other.diagnosticCode, isNot(contains('PRIVATE_CANARY')));
  });
  test('storage read error is not reported as existing account', () {
    final failure = classifyTransferFailure(StateError('Secure candidate read failed'), TransferDiagnosticStage.localProfile);
    expect(failure.code, TransferFailureCode.secureStorage);
  });
  test('timeout retains the operation stage without exception text', () {
    final failure = classifyTransferFailure(TimeoutException('secret-timeout-detail'), TransferDiagnosticStage.waitingForApproval);
    expect(failure.code, TransferFailureCode.timeout);
    expect(failure.stage, TransferDiagnosticStage.waitingForApproval);
    expect(failure.diagnosticCode, isNot(contains('secret')));
  });
  test('proof verification failure stays a blocking verification failure', () {
    expect(classifyTransferFailure(StateError('Invalid transition signature'), TransferDiagnosticStage.verifying).code, TransferFailureCode.verification);
  });
  for (final language in ['ru', 'uk', 'en']) {
    testWidgets('existing-profile message and code are visible $language', (tester) async {
      const failure = TransferFailure(TransferFailureCode.existingProfile, TransferDiagnosticStage.localProfile);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DeviceTransferFailurePanel(failure: failure, language: language))));
      expect(find.text(failure.diagnosticCode), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
