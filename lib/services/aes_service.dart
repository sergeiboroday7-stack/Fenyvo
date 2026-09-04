import 'package:encrypt/encrypt.dart' as encrypt;

class AESService {
  static final encrypt.Key _key =
      encrypt.Key.fromUtf8('spartan_chat_2026_secure_key_32');

  static final encrypt.IV _iv =
      encrypt.IV.fromUtf8('spartan_chat_iv');

  static String encryptMessage(String text) {
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          _key,
          mode: encrypt.AESMode.cbc,
        ),
      );

      final encrypted = encrypter.encrypt(
        text,
        iv: _iv,
      );

      return encrypted.base64;
    } catch (e) {
      print('Ошибка AES шифрования: $e');
      return text;
    }
  }

  static String decryptMessage(String text) {
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          _key,
          mode: encrypt.AESMode.cbc,
        ),
      );

      return encrypter.decrypt64(
        text,
        iv: _iv,
      );
    } catch (e) {
      print('Ошибка AES расшифровки: $e');
      return text;
    }
  }
}