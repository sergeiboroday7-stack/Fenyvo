import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/presence_tracker.dart';

void main() {
  test(
    'online is immediate and offline waits for the presentation grace',
    () async {
      final tracker = PresenceTracker(
        offlineGrace: const Duration(milliseconds: 30),
      );
      addTearDown(tracker.dispose);

      tracker.updateUser('Alice', online: true);
      expect(tracker.isOnline('alice'), isTrue);

      tracker.updateUser('ALICE', online: false);
      expect(tracker.isOnline('Alice'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tracker.isOnline('alice'), isFalse);
    },
  );

  test('returning online cancels a pending offline transition', () async {
    final tracker = PresenceTracker(
      offlineGrace: const Duration(milliseconds: 30),
    );
    addTearDown(tracker.dispose);

    tracker.updateUser('Bob', online: true);
    tracker.updateUser('Bob', online: false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    tracker.updateUser('bob', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(tracker.isOnline('BOB'), isTrue);
    expect(tracker.onlineUsers, contains('bob'));
  });

  test(
    'authoritative snapshots remove missing users after the grace',
    () async {
      final tracker = PresenceTracker(
        offlineGrace: const Duration(milliseconds: 30),
      );
      addTearDown(tracker.dispose);

      tracker.replaceOnline(const ['Alice', 'Bob']);
      tracker.replaceOnline(const ['Alice']);
      expect(tracker.isOnline('Bob'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tracker.isOnline('Alice'), isTrue);
      expect(tracker.isOnline('Bob'), isFalse);
    },
  );

  test('connection loss clears presence immediately', () {
    final tracker = PresenceTracker();
    addTearDown(tracker.dispose);

    tracker.replaceOnline(const ['Alice', 'Bob']);
    tracker.clearImmediately();

    expect(tracker.onlineUsers, isEmpty);
  });
}
