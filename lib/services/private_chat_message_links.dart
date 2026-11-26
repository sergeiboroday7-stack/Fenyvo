import 'temporary_invite_link.dart';

/// Link actions for a decrypted private-chat message. Parsing never joins a
/// temporary session and never modifies the message or its E2EE metadata.
enum PrivateChatMessageLinkKind { temporaryInvite, contact, external }

class PrivateChatMessageLink {
  const PrivateChatMessageLink({
    required this.uri,
    required this.kind,
    this.temporaryToken,
    this.contactUsername,
  });

  final Uri uri;
  final PrivateChatMessageLinkKind kind;
  final String? temporaryToken;
  final String? contactUsername;

  static final _urlPattern = RegExp(r'https://[^\s<>"\x27]+', caseSensitive: false);
  static final _usernamePattern = RegExp(r'^[a-zA-Zа-яА-ЯёЁ0-9_]{3,30}$');
  static const _trailingPunctuation = '.,!?;:)]}»”';

  /// A bounded set of explicit click actions (no automatic navigation).
  static List<PrivateChatMessageLink> extract(String text) {
    if (text.isEmpty || text.length > 8192) return const [];
    final results = <PrivateChatMessageLink>[];
    final seen = <String>{};
    for (final match in _urlPattern.allMatches(text)) {
      var value = match.group(0)!;
      while (value.isNotEmpty &&
          _trailingPunctuation.contains(value[value.length - 1])) {
        value = value.substring(0, value.length - 1);
      }
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !seen.add(uri.toString())) {
        continue;
      }
      if (uri.host.toLowerCase() == 'fenyvo.com' &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 't') {
        final token = TemporaryInviteLink.tokenFromUri(uri);
        if (token == null) continue;
        results.add(PrivateChatMessageLink(
          uri: uri,
          kind: PrivateChatMessageLinkKind.temporaryInvite,
          temporaryToken: token,
        ));
      } else if (uri.host.toLowerCase() == 'fenyvo.com' &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 'u') {
        if (uri.hasPort ||
            uri.query.isNotEmpty ||
            uri.fragment.isNotEmpty ||
            uri.pathSegments.length != 2) continue;
        final user = uri.pathSegments[1].trim();
        if (!_usernamePattern.hasMatch(user)) continue;
        results.add(PrivateChatMessageLink(
          uri: uri,
          kind: PrivateChatMessageLinkKind.contact,
          contactUsername: user,
        ));
      } else {
        results.add(PrivateChatMessageLink(
          uri: uri,
          kind: PrivateChatMessageLinkKind.external,
        ));
      }
      if (results.length >= 3) break;
    }
    return List.unmodifiable(results);
  }
}
