import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/screens/support_payment_screens.dart';

void main() {
  testWidgets('monobank and crypto use separate support pages', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupportOptionsScreen()));

    expect(
      find.byKey(const ValueKey('support-method-monobank')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('support-method-crypto')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-monobank-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('support-crypto-network-list')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('support-method-crypto')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('support-crypto-network-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('support-monobank-button')), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-method-monobank')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('support-monobank-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('support-crypto-network-list')),
      findsNothing,
    );
  });
}
