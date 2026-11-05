// Pure helpers extracted from the private chat screen.
// Preserve compatibility with existing attachment messages.
class PrivateAttachmentHelpers {
  static String messageType(Map<String, dynamic> message) {
    final type = message['messageType']?.toString().trim().toLowerCase() ?? '';
    return type.isEmpty ? 'text' : type;
  }

  static String basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  static String safeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return clean.isEmpty
        ? 'spartan_${DateTime.now().millisecondsSinceEpoch}.bin'
        : clean;
  }

  static String mimeFromName(String name, String fallback) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return fallback;
  }
}
