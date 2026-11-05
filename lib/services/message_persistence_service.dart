import 'package:hive/hive.dart';

import 'message_status_merge.dart';

/// Persist a snapshot of messages and await the Hive write.
Future<void> persistMessagesToHive(
  Box box,
  String key,
  List<Map<String, dynamic>> messages,
) async {
  final messagesToSave = <Map<String, dynamic>>[];

  for (final message in messages) {
    final copy = Map<String, dynamic>.from(message);
    final localPath = copy['localMediaPath']?.toString().trim() ?? '';

    if (localPath.isNotEmpty) {
      copy.remove('mediaData');
      copy.remove('voiceData');
    }

    messagesToSave.add(copy);
  }

  // Keep the highest known delivery/read status for matching messages.
  // This protects this write path from a stale snapshot.
  final rawPersisted = box.get(key);
  final persisted = <Map<String, dynamic>>[];

  if (rawPersisted is List) {
    for (final item in rawPersisted) {
      if (item is Map) {
        persisted.add(Map<String, dynamic>.from(item));
      }
    }
  }

  final guardedMessages = preserveMessageStatus(
    incoming: messagesToSave,
    persisted: persisted,
  );

  await box.put(key, guardedMessages);
}
/// Read the current Hive value, apply a change, then await persistence.
///
/// Returning null from [mutate] skips the write.
/// Call this inside a shared per-chat write coordinator.
Future<bool> mutateMessagesInHive(
  Box box,
  String key,
  List<Map<String, dynamic>>? Function(
    List<Map<String, dynamic>> current,
  ) mutate,
) async {
  final raw = box.get(key);

  if (raw != null && raw is! List) {
    throw StateError('Invalid stored message history');
  }

  final current = <Map<String, dynamic>>[];

  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) {
        throw StateError('Invalid stored message entry');
      }
      current.add(Map<String, dynamic>.from(item));
    }
  }

  final updated = mutate(current);

  if (updated == null) {
    return false;
  }

  await persistMessagesToHive(box, key, updated);
  return true;
}