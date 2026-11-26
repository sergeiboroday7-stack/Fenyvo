/// Strict parser for temporary-contact invitations.
/// Invalid or foreign URLs must never be interpreted as joining tokens.
class TemporaryInviteLink {
  TemporaryInviteLink._();

  static final RegExp _tokenPattern = RegExp(r'^[a-f0-9]{64}$');

  static String? tokenFromUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != 'fenyvo.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 't') {
      return null;
    }
    final token = uri.pathSegments[1].toLowerCase();
    return _tokenPattern.hasMatch(token) ? token : null;
  }

  static String? tokenFromText(String text) {
    final input = text.trim();
    if (input.isEmpty || input.length > 256) return null;
    final token = input.toLowerCase();
    if (_tokenPattern.hasMatch(token)) return token;
    final uri = Uri.tryParse(input);
    return uri == null ? null : tokenFromUri(uri);
  }

  static String urlForToken(String token) {
    final normalized = token.toLowerCase();
    if (!_tokenPattern.hasMatch(normalized)) {
      throw const FormatException('Invalid temporary invitation token');
    }
    return Uri.https('fenyvo.com', '/t/$normalized').toString();
  }
}
