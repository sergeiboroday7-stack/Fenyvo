/// Formats private attachment sizes without depending on Flutter UI.
///
/// The caller provides labels in the current user's language.
class PrivateAttachmentSizeFormatter {
  static String format(
    dynamic raw,
    String Function(String key) label,
  ) {
    final bytes = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 0;

    if (bytes <= 0) return '';

    if (bytes < 1024) {
      return '$bytes ' + label('chatSizeBytes');
    }

    final kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} ' +
          label('chatSizeKilobytes');
    }

    final mb = kb / 1024;

    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} ' +
        label('chatSizeMegabytes');
  }
}