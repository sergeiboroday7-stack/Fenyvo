import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;

import 'rsa_service.dart';

class HybridCryptoService {
  static final Random _random = Random.secure();

  static String encryptMessage(
    String text,
    String recipientPublicKeyStr,
  ) {
    try {
      final aesKeyBytes = Uint8List.fromList(
        List<int>.generate(
          32,
          (_) => _random.nextInt(256),
        ),
      );

      final aesKey = encrypt.Key(aesKeyBytes);

      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          aesKey,
          mode: encrypt.AESMode.cbc,
        ),
      );

      final encryptedMessage = encrypter.encrypt(
        text,
        iv: iv,
      );

      final recipientPublicKey =
          RSAService.deserializePublicKey(
        recipientPublicKeyStr,
      );

      if (recipientPublicKey == null) {
        throw Exception(
          'Не удалось получить публичный ключ получателя',
        );
      }

      final encryptedAesKey =
          RSAService.encryptAESKey(
        aesKeyBytes,
        recipientPublicKey,
      );

      final packet = <String, dynamic>{
        'msg': encryptedMessage.base64,
        'key': encryptedAesKey,
        'iv': iv.base64,
      };

      return jsonEncode(packet);
    } catch (e) {
      print('Ошибка шифрования: $e');
      return text;
    }
  }

  static String decryptMessage(
    String payloadJson,
  ) {
    try {
      final decoded = jsonDecode(payloadJson);

      if (decoded is! Map) {
        return payloadJson;
      }

      final packet =
          Map<String, dynamic>.from(decoded);

      final encryptedKey =
          packet['key']?.toString();

      final encryptedMessage =
          packet['msg']?.toString();

      final ivValue =
          packet['iv']?.toString();

      if (encryptedKey == null ||
          encryptedMessage == null ||
          ivValue == null) {
        return payloadJson;
      }

      final aesKeyBytes =
          RSAService.decryptAESKey(
        encryptedKey,
      );

      final aesKey =
          encrypt.Key(aesKeyBytes);

      final iv =
          encrypt.IV.fromBase64(
        ivValue,
      );

      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          aesKey,
          mode: encrypt.AESMode.cbc,
        ),
      );

      return encrypter.decrypt64(
        encryptedMessage,
        iv: iv,
      );
    } catch (e) {
      print('Ошибка расшифровки: $e');
      return payloadJson;
    }
  }
}