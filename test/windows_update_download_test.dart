import 'dart:io';

import 'package:test/test.dart';

import '../lib/services/windows_update_core.dart';

void main() {
  const expectedHash =
      '24090dc82dd44984ab1327dcb0b5be9a9c272d2b331089945fda26ba82af54a2';

  final downloadUri = Uri.parse(
    'https://fenyvo.com/download/Fenyvo-1.8.2-windows-x64.zip',
  );

  Future<File> download(String hash, Directory temp) {
    return const WindowsUpdateCore().downloadAndVerify(
      uri: downloadUri,
      build: 6296,
      sha256Hex: hash,
      sizeBytes: 31172850,
      temporaryDirectory: temp,
    );
  }

  test('downloads and verifies real Windows release 6296', () async {
    final temp = await Directory.systemTemp.createTemp('fenyvo-test-');

    try {
      final file = await download(expectedHash, temp);

      expect(await file.exists(), isTrue);
      expect(await file.length(), 31172850);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rejects incorrect SHA-256 and removes partial file', () async {
    final temp = await Directory.systemTemp.createTemp('fenyvo-test-');

    try {
      await expectLater(
        download('0' * 64, temp),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Update SHA-256 mismatch',
          ),
        ),
      );

      final updateDir = Directory(
        '${temp.path}${Platform.pathSeparator}fenyvo-updates',
      );

      final partial = File(
        '${updateDir.path}${Platform.pathSeparator}fenyvo-6296.zip.part',
      );

      final completed = File(
        '${updateDir.path}${Platform.pathSeparator}fenyvo-6296.zip',
      );

      expect(await partial.exists(), isFalse);
      expect(await completed.exists(), isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
