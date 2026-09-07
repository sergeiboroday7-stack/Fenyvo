import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class RSAService {
  static late RSAPublicKey publicKey;
  static late RSAPrivateKey privateKey;

  static bool _initialized = false;

  static Future<void> generateKeys() async {
    final secureRandom = _getSecureRandom();

    final keyGenParams = RSAKeyGeneratorParameters(
      BigInt.parse('65537'),
      2048,
      64,
    );

    final keyGenerator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          keyGenParams,
          secureRandom,
        ),
      );

    final keyPair = keyGenerator.generateKeyPair();

    publicKey =
        keyPair.publicKey as RSAPublicKey;

    privateKey =
        keyPair.privateKey as RSAPrivateKey;

    _initialized = true;

    print('🔐 RSA ключи сгенерированы');
  }

  static SecureRandom _getSecureRandom() {
    final random = Random.secure();

    final seed = Uint8List.fromList(
      List<int>.generate(
        32,
        (_) => random.nextInt(256),
      ),
    );

    final secureRandom = SecureRandom('Fortuna');

    secureRandom.seed(
      KeyParameter(seed),
    );

    return secureRandom;
  }

  static String encryptAESKey(
    Uint8List aesKey,
    RSAPublicKey recipientPublicKey,
  ) {
    final cipher = RSAEngine()
      ..init(
        true,
        PublicKeyParameter<RSAPublicKey>(
          recipientPublicKey,
        ),
      );

    final encrypted =
        cipher.process(aesKey);

    return base64Encode(encrypted);
  }

  static Uint8List decryptAESKey(
    String encryptedKey,
  ) {
    if (!_initialized) {
      throw StateError(
        'RSA ключи ещё не сгенерированы',
      );
    }

    final encryptedBytes =
        base64Decode(encryptedKey);

    final cipher = RSAEngine()
      ..init(
        false,
        PrivateKeyParameter<RSAPrivateKey>(
          privateKey,
        ),
      );

    return cipher.process(
      encryptedBytes,
    );
  }

  static String serializePublicKey() {
    if (!_initialized) {
      throw StateError(
        'RSA ключи ещё не сгенерированы',
      );
    }

    final modulus =
        publicKey.modulus!.toRadixString(16);

    final exponent =
        publicKey.exponent!.toRadixString(16);

    final data = <String, String>{
      'modulus': modulus,
      'exponent': exponent,
    };

    return base64Encode(
      utf8.encode(
        jsonEncode(data),
      ),
    );
  }

  static RSAPublicKey? deserializePublicKey(
    String keyStr,
  ) {
    try {
      final decoded = utf8.decode(
        base64Decode(keyStr),
      );

      final data = jsonDecode(decoded);

      if (data is! Map) {
        return null;
      }

      final modulusString =
          data['modulus']?.toString();

      final exponentString =
          data['exponent']?.toString();

      if (modulusString == null ||
          exponentString == null) {
        return null;
      }

      final modulus = BigInt.parse(
        modulusString,
        radix: 16,
      );

      final exponent = BigInt.parse(
        exponentString,
        radix: 16,
      );

      return RSAPublicKey(
        modulus,
        exponent,
      );
    } catch (e) {
      print(
        'Ошибка десериализации публичного ключа: $e',
      );

      return null;
    }
  }

  static bool get isInitialized =>
      _initialized;
}