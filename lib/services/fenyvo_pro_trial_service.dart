import 'package:shared_preferences/shared_preferences.dart';

class FenyvoProTrialSnapshot {
  const FenyvoProTrialSnapshot({required this.startedAt, required this.now});

  final DateTime? startedAt;
  final DateTime now;

  static const duration = Duration(days: 30);

  bool get hasStarted => startedAt != null;
  bool get isActive => remaining > Duration.zero;
  DateTime? get endsAt => startedAt?.add(duration);

  Duration get remaining {
    final end = endsAt;
    if (end == null || !end.isAfter(now)) return Duration.zero;
    return end.difference(now);
  }

  int get daysRemaining {
    if (!isActive) return 0;
    final days = (remaining.inHours / 24).ceil();
    if (days < 1) return 1;
    if (days > 30) return 30;
    return days;
  }
}

/// Local-only preview access. This is deliberately not a billing entitlement.
/// A server-verified subscription will replace it after product testing.
class FenyvoProTrialService {
  FenyvoProTrialService._();

  static const _trialStartKey = 'fenyvo_pro_preview_trial_started_at_v1';

  static Future<FenyvoProTrialSnapshot> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_trialStartKey);
    return FenyvoProTrialSnapshot(
      startedAt: raw == null ? null : DateTime.tryParse(raw)?.toUtc(),
      now: DateTime.now().toUtc(),
    );
  }

  static Future<FenyvoProTrialSnapshot> activate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_trialStartKey);
    if (existing == null) {
      await preferences.setString(
        _trialStartKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    return load();
  }
}
