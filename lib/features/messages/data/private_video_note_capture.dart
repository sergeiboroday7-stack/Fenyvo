import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Camera capture entry point for FENYVO short video notes.
///
/// Capturing and sending are separate operations. No message is
/// transmitted until the user explicitly confirms the preview.
class PrivateVideoNoteCapture {
  PrivateVideoNoteCapture({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const Duration maximumDuration = Duration(seconds: 60);
  static const int maximumBytes = 200 * 1024 * 1024;

  static bool isSupportedPlatform({
    required bool isAndroid,
    required bool isIOS,
  }) {
    return isAndroid || isIOS;
  }

  static bool isValidSize(int bytes) {
    return bytes > 0 && bytes <= maximumBytes;
  }

  Future<XFile?> record() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    // Platform camera UI is used for the initial capture test.
    // The dedicated FENYVO recording overlay will replace it.
    final video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: maximumDuration,
    );

    if (video == null) return null;

    final size = await video.length();
    if (!isValidSize(size)) {
      throw const FileSystemException(
        'Video note exceeds the allowed size or is empty',
      );
    }

    return video;
  }
}
