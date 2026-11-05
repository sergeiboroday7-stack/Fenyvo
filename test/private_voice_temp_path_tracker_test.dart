import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_temp_path_tracker.dart';

void main() {
  test('tracks one temporary recording path', () {
    final tracker = PrivateVoiceTempPathTracker();

    tracker.track('voice_a.m4a');

    expect(tracker.paths, ['voice_a.m4a']);
    expect(tracker.count, 1);
  });

  test('preserves previous path when a new recording begins', () {
    final tracker = PrivateVoiceTempPathTracker();

    tracker.track('voice_a.m4a');
    tracker.track('voice_b.m4a');

    expect(tracker.paths, ['voice_a.m4a', 'voice_b.m4a']);
    expect(tracker.count, 2);
  });

  test('releasing an older path leaves the new path tracked', () {
    final tracker = PrivateVoiceTempPathTracker();

    tracker.track('voice_a.m4a');
    tracker.track('voice_b.m4a');

    tracker.release('voice_a.m4a');

    expect(tracker.paths, ['voice_b.m4a']);
  });

  test('deduplicates paths and supports shutdown clearing', () {
    final tracker = PrivateVoiceTempPathTracker();

    tracker.track('voice_a.m4a');
    tracker.track('voice_a.m4a');
    tracker.track('');

    expect(tracker.count, 1);

    tracker.clear();

    expect(tracker.paths, isEmpty);
    expect(tracker.count, 0);
  });
}
