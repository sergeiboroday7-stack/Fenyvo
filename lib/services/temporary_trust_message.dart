/// Human-readable FENYVO Trust controls transported as ordinary *encrypted*
/// temporary chat messages. Older clients display meaningful text instead of
/// protocol JSON. Parsing a control is not identity verification.
enum TemporaryTrustKind { request, decline, reveal }

class TemporaryTrustMessage {
  const TemporaryTrustMessage(this.kind, {this.username});

  final TemporaryTrustKind kind;
  final String? username;

  static const String requestText =
      '🔒 FENYVO Trust: Можно увидеть ваш профиль?';
  static const String declineText =
      '🔒 FENYVO Trust: Я пока останусь анонимным.';
  static const String _revealPrefix = '🔒 FENYVO Trust: Мой профиль: @';

  static final RegExp _usernamePattern = RegExp(
    r'^[a-zA-Z0-9_а-яА-ЯёЁіІїЇєЄґҐ.\-]{1,64}$',
  );

  static String? revealTextFor(String username) {
    final trimmed = username.trim();
    if (!_usernamePattern.hasMatch(trimmed)) return null;
    return '$_revealPrefix$trimmed';
  }

  static TemporaryTrustMessage? parse(String text) {
    if (text == requestText) {
      return const TemporaryTrustMessage(TemporaryTrustKind.request);
    }
    if (text == declineText) {
      return const TemporaryTrustMessage(TemporaryTrustKind.decline);
    }
    if (text.startsWith(_revealPrefix) && text.length <= 160) {
      final username = text.substring(_revealPrefix.length);
      if (_usernamePattern.hasMatch(username)) {
        return TemporaryTrustMessage(
          TemporaryTrustKind.reveal,
          username: username,
        );
      }
    }
    return null;
  }
}
