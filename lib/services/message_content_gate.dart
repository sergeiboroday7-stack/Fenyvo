/// Checks whether a message has actual text or recognizable media payload.
///
/// This is a structural content check, NOT cryptographic verification.
/// Sender, recipient, authorization, and E2EE validation remain separate.
///
/// Metadata such as messageType, mimeType, and fileName alone is
/// insufficient to make an otherwise empty message valid.
bool hasMessageContent(Map<dynamic, dynamic> message) {
  final text = message['text'];
  if (text is String && text.trim().isNotEmpty) {
    return true;
  }

  for (final field in <String>[
    'mediaId',
    'mediaData',
    'voiceData',
  ]) {
    final value = message[field];
    if (value is String && value.trim().isNotEmpty) {
      return true;
    }
  }

  final encryptedMedia = message['e2eeMedia'];
  if (encryptedMedia is Map && encryptedMedia.isNotEmpty) {
    return encryptedMedia.values.any((value) {
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is List) return value.isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return false;
    });
  }

  return false;
}