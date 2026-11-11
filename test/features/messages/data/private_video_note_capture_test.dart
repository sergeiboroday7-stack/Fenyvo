import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/data/private_video_note_capture.dart';

void main() {
  test('maximum duration is one minute', () {
    expect(
      PrivateVideoNoteCapture.maximumDuration,
      const Duration(seconds: 60),
    );
  });

  test('rejects empty and oversized videos', () {
    expect(PrivateVideoNoteCapture.isValidSize(0), isFalse);
    expect(PrivateVideoNoteCapture.isValidSize(-1), isFalse);
    expect(
      PrivateVideoNoteCapture.isValidSize(
        PrivateVideoNoteCapture.maximumBytes + 1,
      ),
      isFalse,
    );
  });

  test('accepts valid video sizes including the boundary', () {
    expect(PrivateVideoNoteCapture.isValidSize(1024), isTrue);
    expect(
      PrivateVideoNoteCapture.isValidSize(PrivateVideoNoteCapture.maximumBytes),
      isTrue,
    );
  });

  test('camera recording is supported only on mobile', () {
    expect(
      PrivateVideoNoteCapture.isSupportedPlatform(
        isAndroid: true,
        isIOS: false,
      ),
      isTrue,
    );

    expect(
      PrivateVideoNoteCapture.isSupportedPlatform(
        isAndroid: false,
        isIOS: true,
      ),
      isTrue,
    );

    expect(
      PrivateVideoNoteCapture.isSupportedPlatform(
        isAndroid: false,
        isIOS: false,
      ),
      isFalse,
    );
  });
}
