/// Pure UI-level checks: decrypted temporary messages must stay inside their
/// authenticated account, live connection, and the selected temporary session.
/// The socket service performs the cryptographic checks independently.
class TemporaryChatUiGuard {
  const TemporaryChatUiGuard._();

  static final RegExp _session = RegExp(r'^[a-f0-9]{48}$');

  static bool validSession(String sessionId, String role) =>
      _session.hasMatch(sessionId) && (role == 'owner' || role == 'guest');

  static bool live({
    required bool authenticated,
    required String? expectedOwner,
    required String? activeOwner,
    required String? expectedAccountId,
    required String? activeAccountId,
    required int expectedGeneration,
    required int activeGeneration,
  }) =>
      authenticated &&
      expectedOwner != null &&
      expectedOwner.isNotEmpty &&
      expectedOwner == activeOwner &&
      expectedAccountId != null &&
      expectedAccountId.isNotEmpty &&
      expectedAccountId == activeAccountId &&
      expectedGeneration == activeGeneration;

  static bool acceptsMessage({
    required String sessionId,
    required String role,
    required Map<String, dynamic> data,
  }) =>
      validSession(sessionId, role) &&
      data['sessionId'] == sessionId &&
      data['role'] == role &&
      data['e2ee'] == true &&
      data['e2eeVersion'] == 2 &&
      data['e2eeProtocol'] == 'signal' &&
      (data['messageId']?.toString().isNotEmpty ?? false) &&
      (data['text'] is String && (data['text'] as String).isNotEmpty);
}
