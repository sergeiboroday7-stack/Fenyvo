import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bounded, account/session/role scoped history, stored encrypted by the OS.
/// Never grants chat access. A fresh server authorization and existing Signal
/// state are required before a caller may display these records.
class TemporaryHistoryLine {
  const TemporaryHistoryLine({
    required this.text,
    required this.outgoing,
    required this.timestamp,
  });
  final String text;
  final bool outgoing;
  final DateTime timestamp;
}

class TemporaryHistoryCodec {
  static const int maxLines = 60;
  static const int maxCharacters = 16000;
  static final _sessionIdPattern = RegExp(r'^[a-f0-9]{48}$');

  static bool validScope(String accountId, String sessionId, String role) =>
      accountId.trim().isNotEmpty && accountId.length <= 256 &&
      _sessionIdPattern.hasMatch(sessionId) &&
      (role == 'owner' || role == 'guest');

  static String keyFor(String accountId, String sessionId, String role) {
    if (!validScope(accountId, sessionId, role)) {
      throw const FormatException('Invalid temporary history scope');
    }
    final account = base64Url.encode(utf8.encode(accountId));
    return 'fenyvo_trust_history_v1.$account.$sessionId.$role';
  }

  static String encode(List<TemporaryHistoryLine> lines, DateTime expiresAt) {
    if (expiresAt.isBefore(DateTime.now().toUtc())) {
      throw StateError('Cannot persist expired chat history');
    }
    final saved = <Map<String, Object>>[];
    var characters = 0;
    for (final item in lines.reversed) {
      if (saved.length >= maxLines) break;
      if (item.text.isEmpty || item.text.length > 4000) continue;
      if (characters + item.text.length > maxCharacters) break;
      characters += item.text.length;
      saved.add({
        't': item.text,
        'o': item.outgoing,
        'at': item.timestamp.toUtc().toIso8601String(),
      });
    }
    return jsonEncode({
      'v': 1,
      'exp': expiresAt.toUtc().toIso8601String(),
      'lines': saved.reversed.toList(),
    });
  }

  static List<TemporaryHistoryLine> decode(String? source, DateTime now) {
    if (source == null || source.isEmpty || source.length > 40000) return const [];
    try {
      final value = jsonDecode(source);
      if (value is! Map || value['v'] != 1 || value['lines'] is! List) {
        return const [];
      }
      final expiry = DateTime.tryParse(value['exp']?.toString() ?? '');
      if (expiry == null || !expiry.isAfter(now)) return const [];
      final items = value['lines'] as List;
      if (items.length > maxLines) return const [];
      var characters = 0;
      final result = <TemporaryHistoryLine>[];
      for (final item in items) {
        if (item is! Map || item['t'] is! String ||
            item['o'] is! bool || item['at'] is! String) return const [];
        final content = item['t'] as String;
        final date = DateTime.tryParse(item['at'] as String);
        characters += content.length;
        if (content.isEmpty || content.length > 4000 ||
            characters > maxCharacters || date == null) return const [];
        result.add(TemporaryHistoryLine(
          text: content,
          outgoing: item['o'] as bool,
          timestamp: date,
        ));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }
}

class TemporaryChatHistoryStore {
  TemporaryChatHistoryStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  Future<List<TemporaryHistoryLine>> read({
    required String accountId,
    required String sessionId,
    required String role,
  }) async {
    final key = TemporaryHistoryCodec.keyFor(accountId, sessionId, role);
    final raw = await _storage.read(key: key);
    return TemporaryHistoryCodec.decode(raw, DateTime.now().toUtc());
  }

  Future<void> save({
    required String accountId,
    required String sessionId,
    required String role,
    required DateTime expiresAt,
    required List<TemporaryHistoryLine> lines,
  }) => _storage.write(
    key: TemporaryHistoryCodec.keyFor(accountId, sessionId, role),
    value: TemporaryHistoryCodec.encode(lines, expiresAt),
  );

  Future<void> delete({
    required String accountId,
    required String sessionId,
    required String role,
  }) => _storage.delete(
    key: TemporaryHistoryCodec.keyFor(accountId, sessionId, role),
  );
}
