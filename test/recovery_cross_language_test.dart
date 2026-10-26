import 'package:flutter_test/flutter_test.dart';

import '../lib/services/crypto/recovery_signature_service.dart';

void main() {
  test('Dart recovery vector for Node.js', () async {
    const phrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    const challenge =
        'FENYVO/account-password-recovery/v1:testuser:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final service = RecoverySignatureService();
    final keyPair = await service.keyPairFromPhrase(phrase);
    final publicKey = await keyPair.extractPublicKey();
    final signature = await service.signChallenge(phrase, challenge);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    print('DART_PUBLIC_KEY=${hex(publicKey.bytes)}');
    print('DART_SIGNATURE=${hex(signature.bytes)}');
    expect(publicKey.bytes.length, 32);
    expect(signature.bytes.length, 64);
  });
}
