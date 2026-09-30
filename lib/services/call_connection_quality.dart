enum CallConnectionQuality { unknown, good, poor, reconnecting }

CallConnectionQuality evaluateCallConnectionQuality({
  double? packetLossPercent,
  double? roundTripTimeMs,
  double? jitterMs,
  bool reconnecting = false,
}) {
  if (reconnecting) return CallConnectionQuality.reconnecting;
  if (packetLossPercent == null &&
      roundTripTimeMs == null &&
      jitterMs == null) {
    return CallConnectionQuality.unknown;
  }
  if ((packetLossPercent ?? 0) >= 8 ||
      (roundTripTimeMs ?? 0) >= 800 ||
      (jitterMs ?? 0) >= 80) {
    return CallConnectionQuality.poor;
  }
  return CallConnectionQuality.good;
}
