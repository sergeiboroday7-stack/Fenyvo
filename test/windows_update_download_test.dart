import 'dart:io';

import 'package:test/test.dart';

import '../lib/services/windows_update_core.dart';

void main() {
  const expectedHash =
      '1b7d012c8d8f25db8dc48eacb130b4c3c883d5b3a5273aea5dff772a92d4048f';

  final downloadUri = Uri.parse(
    'https://fenyvo.com/download/Fenyvo-1.8.2-windows-x64.zip',
  );

  Future<File> download(String hash, Directory temp) {
    return const WindowsUpdateCore().downloadAndVerify(
      uri: downloadUri,
      build: 4254,
      sha256Hex: hash,
      sizeBytes: 31490214,
      temporaryDirectory: temp,
    );
  }

  test('downloads and verifies real Windows release 4254', () async {
    final temp = await Directory.systemTemp.createTemp('fenyvo-test-');

    try {
      final file = await download(expectedHash, temp);

      expect(await file.exists(), isTrue);
      expect(await file.length(), 31490214);
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
        '${updateDir.path}${Platform.pathSeparator}fenyvo-4254.zip.part',
      );

      final completed = File(
        '${updateDir.path}${Platform.pathSeparator}fenyvo-4254.zip',
      );

      expect(await partial.exists(), isFalse);
      expect(await completed.exists(), isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
