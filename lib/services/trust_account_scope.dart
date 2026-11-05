import 'dart:convert';

/// Builds account-scoped keys for local trust preferences.
///
/// This helper does not migrate legacy global preferences automatically.
/// Legacy keys are ambiguous when multiple accounts use the same device.
class TrustAccountScope {
  const TrustAccountScope._();

  static String? key({
    required String owner,
    required String contact,
    required String prefix,
  }) {
    final normalizedOwner = owner.trim().toLowerCase();
    final normalizedContact = contact.trim().toLowerCase();

    if (normalizedOwner.isEmpty ||
        normalizedContact.isEmpty ||
        normalizedOwner == normalizedContact ||
        prefix.isEmpty) {
      return null;
    }

    String encode(String value) =>
        base64Url.encode(utf8.encode(value));

    return '${prefix}v2_'
        '${encode(normalizedOwner)}_'
        '${encode(normalizedContact)}';
  }

  static String? reasonKey({
    required String owner,
    required String contact,
    required String prefix,
  }) {
    final base = key(
      owner: owner,
      contact: contact,
      prefix: prefix,
    );

    return base == null ? null : '${base}_reason';
  }
}