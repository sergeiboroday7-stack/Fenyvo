import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Owns temporary audio recording paths and cleanup.
/// Does not send messages or change encryption.
class PrivateVoiceRecordingFiles {
  const PrivateVoiceRecordingFiles._();

  static String pathFor({
    required String temporaryRoot,
    required int timestampMicros,
  }) {
    final separator = Platform.pathSeparator;

    return '$temporaryRoot${separator}spartan_voice'
        '${separator}voice_$timestampMicros.m4a';
  }

  static Future<String> createPath() async {
    final temporaryDirectory = await getTemporaryDirectory();

    final voiceDirectory = Directory(
      '${temporaryDirectory.path}'
      '${Platform.pathSeparator}spartan_voice',
    );

    if (!voiceDirectory.existsSync()) {
      await voiceDirectory.create(recursive: true);
    }

    return pathFor(
      temporaryRoot: temporaryDirectory.path,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    );
  }

  static Future<void> deleteIfExists(String path) async {
    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }
  }
}
