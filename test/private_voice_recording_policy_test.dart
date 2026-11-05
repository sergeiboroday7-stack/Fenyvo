import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_voice_recording_policy.dart';

void main() {
  group('PrivateVoiceRecordingPolicy', () {
    test('short recordings are discarded at the exact boundary', () {
      expect(
        PrivateVoiceRecordingPolicy.shouldDiscard(
          send: true,
          duration: const Duration(milliseconds: 649),
        ),
        isTrue,
      );

      expect(
        PrivateVoiceRecordingPolicy.shouldDiscard(
          send: true,
          duration: const Duration(milliseconds: 650),
        ),
        isFalse,
      );
    });

    test('cancellation discards even a valid recording', () {
      expect(
        PrivateVoiceRecordingPolicy.shouldDiscard(
          send: false,
          duration: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });

    test('five-minute boundary automatically finishes recording', () {
      expect(
        PrivateVoiceRecordingPolicy.shouldAutoFinish(
          const Duration(minutes: 4, seconds: 59),
        ),
        isFalse,
      );

      expect(
        PrivateVoiceRecordingPolicy.shouldAutoFinish(
          const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    test('20 MiB maximum accepts boundary and rejects larger files', () {
      final maxBytes = PrivateVoiceRecordingPolicy.maximumFileBytes;

      expect(PrivateVoiceRecordingPolicy.isTooLarge(maxBytes), isFalse);

      expect(PrivateVoiceRecordingPolicy.isTooLarge(maxBytes + 1), isTrue);
    });
  });
}
