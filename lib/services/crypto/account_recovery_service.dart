import 'package:bip39/bip39.dart' as bip39;

class AccountRecoveryService {
  const AccountRecoveryService();

  String generateRecoveryPhrase() {
    return bip39.generateMnemonic(strength: 128);
  }

  bool validateRecoveryPhrase(String phrase) {
    final normalized = phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    return bip39.validateMnemonic(normalized);
  }
}
