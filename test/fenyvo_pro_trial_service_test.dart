import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/fenyvo_pro_trial_service.dart';

void main() {
  test('new Fenyvo Pro preview has not started', () {
    final now = DateTime.utc(2026, 11, 6, 12);
    final snapshot = FenyvoProTrialSnapshot(startedAt: null, now: now);

    expect(snapshot.hasStarted, isFalse);
    expect(snapshot.isActive, isFalse);
    expect(snapshot.daysRemaining, 0);
  });

  test('preview remains active for 30 days', () {
    final start = DateTime.utc(2026, 11, 1, 12);
    final snapshot = FenyvoProTrialSnapshot(
      startedAt: start,
      now: start.add(const Duration(days: 5, hours: 1)),
    );

    expect(snapshot.hasStarted, isTrue);
    expect(snapshot.isActive, isTrue);
    expect(snapshot.daysRemaining, 25);
  });

  test('preview expires after day 30', () {
    final start = DateTime.utc(2026, 11, 1, 12);
    final snapshot = FenyvoProTrialSnapshot(
      startedAt: start,
      now: start.add(const Duration(days: 30)),
    );

    expect(snapshot.isActive, isFalse);
    expect(snapshot.daysRemaining, 0);
  });
}
