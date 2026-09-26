import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/e2ee_media_cipher.dart';

void main() {
  test('E2EE media round-trip preserves a multi-chunk file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'spartan_e2ee_media_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final source = File('${directory.path}${Platform.pathSeparator}source.bin');
    final encrypted = File(
      '${directory.path}${Platform.pathSeparator}encrypted.bin',
    );
    final decrypted = File(
      '${directory.path}${Platform.pathSeparator}decrypted.bin',
    );
    final bytes = Uint8List.fromList(
      List<int>.generate(180000, (index) => (index * 31) & 0xff),
    );
    await source.writeAsBytes(bytes);

    final result = await E2eeMediaCipher.encryptFile(
      sourcePath: source.path,
      targetPath: encrypted.path,
    );
    expect(await encrypted.readAsBytes(), isNot(bytes));
    expect(result.metadata['algorithm'], 'AES-256-GCM');

    await E2eeMediaCipher.decryptFile(
      sourcePath: encrypted.path,
      targetPath: decrypted.path,
      metadata: result.metadata,
    );
    expect(await decrypted.readAsBytes(), bytes);
  });

  test('E2EE media rejects modified ciphertext', () async {
    final directory = await Directory.systemTemp.createTemp(
      'spartan_e2ee_tamper_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final source = File('${directory.path}${Platform.pathSeparator}source.bin');
    final encrypted = File(
      '${directory.path}${Platform.pathSeparator}encrypted.bin',
    );
    final decrypted = File(
      '${directory.path}${Platform.pathSeparator}decrypted.bin',
    );
    await source.writeAsBytes(
      List<int>.generate(4097, (index) => index & 0xff),
    );

    final result = await E2eeMediaCipher.encryptFile(
      sourcePath: source.path,
      targetPath: encrypted.path,
    );
    final damaged = await encrypted.readAsBytes();
    damaged[damaged.length ~/ 2] ^= 0x01;
    await encrypted.writeAsBytes(damaged);

    await expectLater(
      E2eeMediaCipher.decryptFile(
        sourcePath: encrypted.path,
        targetPath: decrypted.path,
        metadata: result.metadata,
      ),
      throwsA(anything),
    );
    expect(await decrypted.exists(), isFalse);
  });
}
