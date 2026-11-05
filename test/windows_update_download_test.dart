import 'dart:io';

import 'package:test/test.dart';

import '../lib/services/windows_update_core.dart';

void main() {
  const expectedHash =
      'eab47d944ad369857837adb163e2477d38aa05040aec3a7bc59cb7b6ea26ee28';

  final downloadUri = Uri.parse(
    'https://fenyvo.com/download/Fenyvo-1.8.2-windows-x64.zip',
  );

  Future<File> download(String hash, Directory temp) {
    return const WindowsUpdateCore().downloadAndVerify(
      uri: downloadUri,
      build: 4256,
      sha256Hex: hash,
      sizeBytes: 31519845,
      temporaryDirectory: temp,
    );
  }

  test('downloads and verifies real Windows release 4256', () async {
    final temp = await Directory.systemTemp.createTemp('fenyvo-test-');

    try {
      final file = await download(expectedHash, temp);

      expect(await file.exists(), isTrue);
      expect(await file.length(), 31519845);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rejects incorrect SHA-256 and removes partial file', () async {
    final temp = await Directory.systemTemp.createTemp('fenyvo-test-');

    try {
      await expectLater(
        download('0' * 64, temp),
        throwsA(isA<FormatException>()),
      );

      final updateDir = Directory(
        '${temp.path}${Platform.pathSeparator}fenyvo-updates',
      );

      final partial = File(
        '${updateDir.path}${Platform.pathSeparator}fenyvo-4256.zip.part',
      );

      final completed = File(
        '${updateDir.path}${Platform.pathSeparator}fenyvo-4256.zip',
      );

      expect(await partial.exists(), isFalse);
      expect(await completed.exists(), isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
