class ShieldAssessment {
  const ShieldAssessment({required this.reason, required this.level});

  final String reason;
  final String level;
}

class FenyvoShieldService {
  FenyvoShieldService._();

  static final RegExp _url = RegExp(
    r'(https?://|www\.)[^\s]+',
    caseSensitive: false,
  );
  static final RegExp _code = RegExp(
    r'(код|парол|одноразов|otp|pin|пин|verification|confirm)',
    caseSensitive: false,
  );
  static final RegExp _money = RegExp(
    r'(деньг|перевод|оплат|карт|сч[её]т|money|payment|bank)',
    caseSensitive: false,
  );
  static final RegExp _urgency = RegExp(
    r'(срочно|немедленно|прямо сейчас|быстрее|urgent|immediately|asap)',
    caseSensitive: false,
  );

  static ShieldAssessment? assess(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;

    final hasUrl = _url.hasMatch(value);
    final hasCode = _code.hasMatch(value);
    final hasMoney = _money.hasMatch(value);
    final hasUrgency = _urgency.hasMatch(value);
    final signals = [
      hasUrl,
      hasCode,
      hasMoney,
      hasUrgency,
    ].where((item) => item).length;

    if ((hasCode && (hasUrgency || hasUrl)) ||
        (hasMoney && hasUrgency) ||
        (hasUrl && hasUrgency && signals >= 2)) {
      return const ShieldAssessment(
        reason: 'Сообщение похоже на попытку получить код, деньги или доступ.',
        level: 'high',
      );
    }
    if ((hasCode && hasMoney) || (hasUrl && hasCode) || signals >= 3) {
      return const ShieldAssessment(
        reason: 'В сообщении обнаружены признаки, требующие проверки.',
        level: 'medium',
      );
    }
    return null;
  }
}
