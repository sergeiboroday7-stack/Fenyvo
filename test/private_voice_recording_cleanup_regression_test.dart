import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_recording_files.dart';

void main() {
  test('cleanup is idempotent after a recording was cancelled', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fenyvo_voice_idempotent_',
    );

    try {
      final file = File('${directory.path}${Platform.pathSeparator}voice.m4a');

      await file.writeAsBytes([1, 2, 3]);

      await PrivateVoiceRecordingFiles.deleteIfExists(file.path);
      await PrivateVoiceRecordingFiles.deleteIfExists(file.path);

      expect(await file.exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('cleanup removes only the specified recording file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fenyvo_voice_isolated_',
    );

    try {
      final first = File('${directory.path}${Platform.pathSeparator}first.m4a');
      final second = File(
        '${directory.path}${Platform.pathSeparator}second.m4a',
      );

      await first.writeAsBytes([1, 2]);
      await second.writeAsBytes([3, 4]);

      await PrivateVoiceRecordingFiles.deleteIfExists(first.path);

      expect(await first.exists(), isFalse);
      expect(await second.exists(), isTrue);
      expect(await second.readAsBytes(), [3, 4]);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
