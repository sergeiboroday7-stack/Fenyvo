enum CallOutcome { completed, missed, declined, cancelled, failed }

class CallResult {
  const CallResult({
    required this.id,
    required this.peer,
    required this.video,
    required this.incoming,
    required this.outcome,
    required this.duration,
    required this.message,
  });
  final String id;
  final String peer;
  final bool video;
  final bool incoming;
  final CallOutcome outcome;
  final Duration duration;
  final String message;

  static CallOutcome remoteEnd({
    required bool incoming,
    required bool connected,
    required bool accepted,
  }) => connected
      ? CallOutcome.completed
      : incoming && !accepted
      ? CallOutcome.missed
      : CallOutcome.failed;
}
