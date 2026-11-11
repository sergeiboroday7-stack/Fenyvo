/// Controls whether message text may be supplied to external text services.
///
/// This is a defense-in-depth guard. It must not replace the existing
/// end-to-end encryption or the restrictions in message context menus.
class PrivateExternalTextPolicy {
  const PrivateExternalTextPolicy._();

  static bool canSendMessage(
    Map<String, dynamic> message, {
    required bool isChatE2eeActive,
  }) {
    if (isChatE2eeActive) {
      return false;
    }

    final e2ee = message['e2ee'];

    // Be conservative if persisted data represents the flag as a string.
    if (e2ee == true || e2ee?.toString().toLowerCase() == 'true') {
      return false;
    }

    // Encrypted-media metadata is also treated conservatively.
    if (message['e2eeMedia'] != null) {
      return false;
    }

    return true;
  }
}
