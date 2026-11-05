/// Adds a message to the latest chat history without replacing it.
///
/// Returns null when the message already exists or has insufficient
/// identity data. The caller should skip persistence when null.
///
/// This does not provide deletion tombstones: a late, previously
/// deleted message still needs separate replay protection.
List<Map<String, dynamic>>? appendMessageIfMissing(
  List<Map<String, dynamic>> current,
  Map<String, dynamic> incoming,
) {
  final id = incoming['id']?.toString().trim() ?? '';
  final from = incoming['from']?.toString().trim() ?? '';
  final to = incoming['to']?.toString().trim() ?? '';
  final time = incoming['time']?.toString().trim() ?? '';
  final text = incoming['text']?.toString() ?? '';

  if (from.isEmpty || to.isEmpty) {
    return null;
  }

  if (id.isEmpty && (time.isEmpty || text.isEmpty)) {
    return null;
  }

  for (final existing in current) {
    final oldId = existing['id']?.toString().trim() ?? '';
    final oldFrom = existing['from']?.toString().trim() ?? '';
    final oldTo = existing['to']?.toString().trim() ?? '';

    if (id.isNotEmpty && oldId.isNotEmpty && id == oldId) {
      // An identical ID for another sender is ambiguous. Fail closed.
      return null;
    }

    if (id.isEmpty &&
        oldFrom == from &&
        oldTo == to &&
        existing['time']?.toString().trim() == time &&
        existing['text']?.toString() == text) {
      return null;
    }
  }

  return <Map<String, dynamic>>[
    for (final message in current) Map<String, dynamic>.from(message),
    Map<String, dynamic>.from(incoming),
  ];
}