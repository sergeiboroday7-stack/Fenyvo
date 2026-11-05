import 'package:hive/hive.dart';

import 'message_persistence_service.dart';
import 'message_status_persistence_service.dart';
import 'message_status_transition.dart';
import 'message_write_coordinator.dart';

/// Updates a persisted outgoing message without requiring an open chat.
///
/// Every writer to the same Hive key must use the same coordinator.
/// This component does not send network acknowledgements.
class MessageStatusHiveWriter {
  MessageStatusHiveWriter({
    required this.box,
    required this.coordinator,
  });

  final Box box;
  final MessageWriteCoordinator coordinator;

  Future<StatusPersistenceOutcome> apply({
    required String key,
    required String currentUser,
    required String peer,
    required String messageId,
    required String eventType,
    required String from,
    required String to,
  }) async {
    final owner = currentUser.trim();
    final contact = peer.trim();
    final id = messageId.trim();

    if (key.isEmpty ||
        owner.isEmpty ||
        contact.isEmpty ||
        id.isEmpty ||
        from != owner ||
        to != contact ||
        (eventType != 'message_delivered' &&
            eventType != 'message_read')) {
      return StatusPersistenceOutcome.rejected;
    }

    return coordinator.run<StatusPersistenceOutcome>(key, () async {
      final raw = box.get(key);
      if (raw is! List) {
        return StatusPersistenceOutcome.missing;
      }

      final messages = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          messages.add(Map<String, dynamic>.from(item));
        }
      }

      final matches = messages.where(
        (message) => message['id']?.toString().trim() == id,
      ).toList();

      if (matches.isEmpty) {
        return StatusPersistenceOutcome.missing;
      }

      if (matches.length != 1) {
        return StatusPersistenceOutcome.rejected;
      }

      final message = matches.single;
      if (message['from']?.toString() != owner ||
          message['to']?.toString() != contact ||
          message['isMe'] == false) {
        return StatusPersistenceOutcome.rejected;
      }

      const ranks = <String, int>{
        'queued': 1,
        'sending': 2,
        'sent': 3,
        'delivered': 4,
        'read': 5,
      };

      final desired = eventType == 'message_read' ? 5 : 4;
      final existing = ranks[message['status']?.toString()] ?? 0;

      if (existing >= desired) {
        return StatusPersistenceOutcome.alreadyApplied;
      }

      final updated = applyMessageStatusTransition(
        messages: messages,
        currentUser: owner,
        peer: contact,
        messageId: id,
        eventType: eventType,
        from: from,
        to: to,
      );

      if (updated == null) {
        return StatusPersistenceOutcome.rejected;
      }

      await persistMessagesToHive(box, key, updated);
      return StatusPersistenceOutcome.updated;
    });
  }
}