/// Compares message identities without using message text when stable IDs exist.
bool isSameStoredMessage(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final firstId = first['id']?.toString().trim() ?? '';
  final secondId = second['id']?.toString().trim() ?? '';

  if (firstId.isNotEmpty || secondId.isNotEmpty) {
    return firstId.isNotEmpty &&
        secondId.isNotEmpty &&
        firstId == secondId;
  }

  return first['from'] == second['from'] &&
      first['to'] == second['to'] &&
      first['text'] == second['text'] &&
      first['time'] == second['time'];
}