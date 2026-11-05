import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_recording_files.dart';

void main() {
  test('uses the established voice recording directory', () {
    final path = PrivateVoiceRecordingFiles.pathFor(
      temporaryRoot: Directory.systemTemp.path,
      timestampMicros: 12345,
    );

    expect(
      path,
      contains(
        '${Platform.pathSeparator}spartan_voice'
        '${Platform.pathSeparator}voice_12345.m4a',
      ),
    );
  });

  test('deletes an abandoned temporary recording', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fenyvo_voice_cleanup_',
    );

    try {
      final file = File(
        '${directory.path}${Platform.pathSeparator}recording.m4a',
      );

      await file.writeAsBytes([1, 2, 3]);

      expect(await file.exists(), isTrue);

      await PrivateVoiceRecordingFiles.deleteIfExists(file.path);

      expect(await file.exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('cleanup tolerates an already missing file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fenyvo_voice_missing_',
    );

    try {
      final path = '${directory.path}${Platform.pathSeparator}missing.m4a';

      await PrivateVoiceRecordingFiles.deleteIfExists(path);

      expect(await File(path).exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
