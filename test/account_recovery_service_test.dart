import 'package:flutter_test/flutter_test.dart';

import '../lib/services/crypto/account_recovery_service.dart';

void main() {
  const service = AccountRecoveryService();

  test('Generates 12 valid recovery words', () {
    final phrase = service.generateRecoveryPhrase();
    expect(phrase.split(' ').length, 12);
    expect(service.validateRecoveryPhrase(phrase), isTrue);
  });

  test('Rejects invalid recovery phrase', () {
    expect(service.validateRecoveryPhrase('invalid words'), isFalse);
  });

  test('Normalizes whitespace and case', () {
    final phrase = service.generateRecoveryPhrase();
    final modified = '  ${phrase.toUpperCase().replaceAll(' ', '  ')}  ';
    expect(service.validateRecoveryPhrase(modified), isTrue);
  });
}
