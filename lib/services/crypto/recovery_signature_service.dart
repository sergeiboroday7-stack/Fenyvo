import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

class RecoverySignatureService {
  const RecoverySignatureService();

  Ed25519 get algorithm => Ed25519();

  Future<SimpleKeyPair> keyPairFromPhrase(String phrase) async {
    final normalized = phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (normalized.split(' ').length != 12 || !bip39.validateMnemonic(normalized)) {
      throw const FormatException('Invalid recovery phrase');
    }

    final seed = bip39.mnemonicToSeed(normalized);
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await kdf.deriveKey(
      secretKey: SecretKey(seed),
      nonce: utf8.encode('FENYVO/account-recovery/salt/v1'),
      info: utf8.encode('FENYVO/account-recovery/ed25519/v1'),
    );
    final keyBytes = await key.extractBytes();
    return algorithm.newKeyPairFromSeed(keyBytes);
  }

  Future<Signature> signChallenge(String phrase, String challenge) async {
    if (challenge.isEmpty) {
      throw const FormatException('Empty recovery challenge');
    }
    final keyPair = await keyPairFromPhrase(phrase);
    return algorithm.sign(utf8.encode(challenge), keyPair: keyPair);
  }
}
