/// Controls whether the legacy-media sharing action may be shown.
///
/// This is only a conservative UI filter, not proof of media ownership.
/// The server independently authorizes every actual regrant.
class LegacyMediaRegrantVisibility {
  static bool canOffer({
    required Map<String, dynamic> message,
    required String currentUser,
    required String recipient,
    required bool communicationAccepted,
  }) {
    final me = currentUser.trim();
    final peer = recipient.trim();
    final from = message['from']?.toString().trim() ?? '';
    final mediaId = message['mediaId']?.toString().trim() ?? '';
    final forwardedFrom =
        message['forwardedFrom']?.toString().trim() ?? '';
    final type =
        message['messageType']?.toString().trim().toLowerCase() ?? '';

    const mediaTypes = {'image', 'video', 'file', 'voice'};

    if (me.isEmpty ||
        peer.isEmpty ||
        me.toLowerCase() == peer.toLowerCase() ||
        !communicationAccepted ||
        message['isMe'] != true ||
        from != me ||
        forwardedFrom.isNotEmpty ||
        message['e2ee'] == true ||
        message['e2eeMedia'] != null ||
        !mediaTypes.contains(type) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,120}$').hasMatch(mediaId)) {
      return false;
    }

    return true;
  }
}