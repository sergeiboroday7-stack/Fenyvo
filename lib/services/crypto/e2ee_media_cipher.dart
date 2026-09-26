import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class E2eeMediaEncryptionResult {
  const E2eeMediaEncryptionResult({
    required this.encryptedPath,
    required this.metadata,
  });

  final String encryptedPath;
  final Map<String, dynamic> metadata;
}

/// Encrypts attachment bytes before they reach the media server.
///
/// The random file key is transported only inside the existing Signal
/// envelope. AES-GCM authenticates the complete ciphertext, so modified or
/// truncated server data is rejected during decryption.
class E2eeMediaCipher {
  E2eeMediaCipher._();

  static const _version = 1;
  static const _algorithm = 'AES-256-GCM';
  static final Uint8List _aad = Uint8List.fromList(
    utf8.encode('spartan-e2ee-media-v1'),
  );

  static Future<E2eeMediaEncryptionResult> encryptFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Файл для шифрования не найден', sourcePath);
    }
    final plaintextSize = await source.length();
    if (plaintextSize <= 0) {
      throw FileSystemException('Файл для шифрования пустой', sourcePath);
    }

    final random = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    try {
      await _transform(
        source: source,
        target: target,
        key: key,
        nonce: nonce,
        encrypt: true,
      );
      return E2eeMediaEncryptionResult(
        encryptedPath: target.path,
        metadata: <String, dynamic>{
          'version': _version,
          'algorithm': _algorithm,
          'key': base64UrlEncode(key),
          'nonce': base64UrlEncode(nonce),
          'plaintextSize': plaintextSize,
        },
      );
    } catch (_) {
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    }
  }

  static Future<void> decryptFile({
    required String sourcePath,
    required String targetPath,
    required Map<String, dynamic> metadata,
  }) async {
    if (int.tryParse(metadata['version']?.toString() ?? '') != _version ||
        metadata['algorithm']?.toString() != _algorithm) {
      throw const FormatException('Неподдерживаемый формат E2EE-медиа');
    }
    final key = _decodeExact(metadata['key'], 32, 'ключ');
    final nonce = _decodeExact(metadata['nonce'], 12, 'nonce');
    final expectedSize = int.tryParse(
      metadata['plaintextSize']?.toString() ?? '',
    );
    if (expectedSize == null || expectedSize <= 0) {
      throw const FormatException('Некорректный размер E2EE-медиа');
    }

    final source = File(sourcePath);
    final target = File(targetPath);
    if (!await source.exists()) {
      throw FileSystemException('Зашифрованный файл не найден', sourcePath);
    }
    await target.parent.create(recursive: true);

    try {
      await _transform(
        source: source,
        target: target,
        key: key,
        nonce: nonce,
        encrypt: false,
      );
      if (await target.length() != expectedSize) {
        throw const FormatException(
          'Размер расшифрованного файла не совпадает',
        );
      }
    } catch (_) {
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    }
  }

  static Future<void> _transform({
    required File source,
    required File target,
    required Uint8List key,
    required Uint8List nonce,
    required bool encrypt,
  }) async {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, _aad));
    final sink = target.openWrite();
    try {
      await for (final rawChunk in source.openRead()) {
        final chunk = Uint8List.fromList(rawChunk);
        final output = Uint8List(chunk.length + 32);
        final written = cipher.processBytes(chunk, 0, chunk.length, output, 0);
        if (written > 0) sink.add(Uint8List.sublistView(output, 0, written));
      }
      final finalOutput = Uint8List(32);
      final finalWritten = cipher.doFinal(finalOutput, 0);
      if (finalWritten > 0) {
        sink.add(Uint8List.sublistView(finalOutput, 0, finalWritten));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static Uint8List _decodeExact(Object? value, int length, String label) {
    try {
      final decoded = base64Url.decode(value?.toString() ?? '');
      if (decoded.length == length) return decoded;
    } catch (_) {}
    throw FormatException('Некорректный $label E2EE-медиа');
  }
}
