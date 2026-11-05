import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_voice_recording_gesture_policy.dart';

void main() {
  group('PrivateVoiceRecordingGesturePolicy', () {
    test('cancels at exact leftward boundary', () {
      expect(PrivateVoiceRecordingGesturePolicy.shouldCancel(-105), isTrue);

      expect(PrivateVoiceRecordingGesturePolicy.shouldCancel(-104.9), isFalse);
    });

    test('rightward movement does not cancel', () {
      expect(PrivateVoiceRecordingGesturePolicy.shouldCancel(105), isFalse);

      expect(PrivateVoiceRecordingGesturePolicy.shouldCancel(0), isFalse);
    });

    test('locks at exact upward boundary', () {
      expect(PrivateVoiceRecordingGesturePolicy.shouldLock(-90), isTrue);

      expect(PrivateVoiceRecordingGesturePolicy.shouldLock(-89.9), isFalse);
    });

    test('downward movement does not lock', () {
      expect(PrivateVoiceRecordingGesturePolicy.shouldLock(90), isFalse);

      expect(PrivateVoiceRecordingGesturePolicy.shouldLock(0), isFalse);
    });
  });
}
