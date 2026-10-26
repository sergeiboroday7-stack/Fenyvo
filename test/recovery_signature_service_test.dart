import 'package:flutter_test/flutter_test.dart';

import '../lib/services/crypto/recovery_signature_service.dart';

void main() {
  const service = RecoverySignatureService();
  const phraseA =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const phraseB =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

  test('Same phrase produces same public key', () async {
    final first = await service.keyPairFromPhrase(phraseA);
    final second = await service.keyPairFromPhrase(phraseA);
    final firstPublic = await first.extractPublicKey();
    final secondPublic = await second.extractPublicKey();
    expect(firstPublic.bytes, orderedEquals(secondPublic.bytes));
  });

  test('Different phrases produce different public keys', () async {
    final first = await service.keyPairFromPhrase(phraseA);
    final second = await service.keyPairFromPhrase(phraseB);
    final firstPublic = await first.extractPublicKey();
    final secondPublic = await second.extractPublicKey();
    expect(firstPublic.bytes, isNot(orderedEquals(secondPublic.bytes)));
  });

  test('Invalid phrase is rejected', () async {
    expect(
      () => service.keyPairFromPhrase('invalid words'),
      throwsA(isA<FormatException>()),
    );
  });
  test('Valid signature verifies', () async {
    final signature = await service.signChallenge(
      phraseA,
      'test-challenge-123',
    );
    final valid = await service.algorithm.verify(
      'test-challenge-123'.codeUnits,
      signature: signature,
    );
    expect(valid, isTrue);
  });

  test('Changed challenge rejects signature', () async {
    final signature = await service.signChallenge(
      phraseA,
      'test-challenge-123',
    );
    final valid = await service.algorithm.verify(
      'test-challenge-456'.codeUnits,
      signature: signature,
    );
    expect(valid, isFalse);
  });

  test('Empty challenge is rejected', () async {
    await expectLater(
      service.signChallenge(phraseA, ''),
      throwsA(isA<FormatException>()),
    );
  });
}
