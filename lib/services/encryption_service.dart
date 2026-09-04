import 'package:encrypt/encrypt.dart';

class EncryptionService {
  static final _key = Key.fromUtf8('12345678901234567890123456789012'); // 32 байта
  static final _iv = IV.fromUtf8('1234567890123456'); // 16 байт
  static final _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  static String encrypt(String plainText) {
    try {
      final encrypted = _encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      return plainText;
    }
  }

  static String decrypt(String encryptedText) {
    try {
      final decrypted = _encrypter.decrypt(Encrypted.fromBase64(encryptedText), iv: _iv);
      return decrypted;
    } catch (e) {
      return encryptedText;
    }
  }
}