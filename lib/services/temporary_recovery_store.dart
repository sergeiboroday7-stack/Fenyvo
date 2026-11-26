import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Metadata only. Never stores plaintext messages, Signal secrets or server
/// authorization decisions. A saved entry must be re-authorized by the server
/// after authentication and before it is shown as an active chat.
class TemporaryRecoveryEntry {
  const TemporaryRecoveryEntry({
    required this.sessionId,
    required this.role,
    required this.expiresAt,
    this.invitationToken,
  });

  final String sessionId;
  final String role;
  final DateTime expiresAt;
  /// An invitation is a bearer secret: stored only in platform secure storage.
  /// Only guests need it for the server's existing rejoin operation.
  final String? invitationToken;

  static final RegExp _session = RegExp(r'^[a-f0-9]{48}$');
  static final RegExp _token = RegExp(r'^[a-f0-9]{64}$');

  bool validAt(DateTime now) =>
      _session.hasMatch(sessionId) &&
      (role == 'guest' || role == 'owner') &&
      expiresAt.isAfter(now) &&
      expiresAt.isBefore(now.add(const Duration(days: 31))) &&
      (role == 'guest'
          ? invitationToken != null && _token.hasMatch(invitationToken!)
          : invitationToken == null);

  Map<String, Object> toJson() => <String, Object>{
        'id': sessionId,
        'role': role,
        'exp': expiresAt.toUtc().toIso8601String(),
        if (invitationToken != null) 'token': invitationToken!,
      };

  static TemporaryRecoveryEntry? fromJson(Object? value, DateTime now) {
    if (value is! Map) return null;
    final id = value['id'];
    final role = value['role'];
    final exp = value['exp'];
    final token = value['token'];
    if (id is! String || role is! String || exp is! String ||
        (token != null && token is! String)) return null;
    final expiresAt = DateTime.tryParse(exp);
    if (expiresAt == null) return null;
    final entry = TemporaryRecoveryEntry(
      sessionId: id,
      role: role,
      expiresAt: expiresAt,
      invitationToken: token as String?,
    );
    return entry.validAt(now) ? entry : null;
  }
}

/// Pure codec for testing without platform channels.
class TemporaryRecoveryCodec {
  /// Avoid an arbitrary choice between multiple guest sessions. Owner
  /// entries are deliberately not candidates: owner access needs an explicit
  /// server-side restoration confirmation that is not available yet.
  static TemporaryRecoveryEntry? singleGuestCandidate(
    List<TemporaryRecoveryEntry> entries, DateTime now,
  ) {
    final guests = entries.where((entry) =>
        entry.role == 'guest' && entry.validAt(now)).toList();
    return guests.length == 1 ? guests.single : null;
  }

  /// A guest may resume only when both secure local metadata and an
  /// authenticated server listing contain the same still-active session.
  /// An owner chat being active must not suppress guest recovery.
  /// Multiple eligible guests remain manual: never pick one arbitrarily.
  static TemporaryRecoveryEntry? confirmedGuest(
    List<TemporaryRecoveryEntry> local,
    List<Map<String, dynamic>> server,
    Set<String> activeSessionIds,
    DateTime now,
  ) {
    final authorized = <String, DateTime>{};
    for (final record in server) {
      final id = record['sessionId'];
      final role = record['role'];
      final rawExpiration = record['expiresAt'];
      if (id is! String || role != 'guest' ||
          rawExpiration is! String ||
          !RegExp(r'^[a-f0-9]{48}$').hasMatch(id)) continue;
      final expiry = DateTime.tryParse(rawExpiration)?.toUtc();
      if (expiry != null && expiry.isAfter(now)) authorized[id] = expiry;
    }
    final candidates = <TemporaryRecoveryEntry>[];
    for (final entry in local) {
      if (entry.role != 'guest' || !entry.validAt(now) ||
          activeSessionIds.contains(entry.sessionId)) continue;
      final expiry = authorized[entry.sessionId];
      if (expiry == null) continue;
      final effectiveExpiry = entry.expiresAt.isBefore(expiry)
          ? entry.expiresAt : expiry;
      candidates.add(TemporaryRecoveryEntry(
        sessionId: entry.sessionId,
        role: 'guest',
        expiresAt: effectiveExpiry,
        invitationToken: entry.invitationToken,
      ));
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Select only owner records that are present both in this account's
  /// secure local metadata and in a fresh authenticated server listing.
  /// Neither source independently grants access. Keep all matching sessions.
  static List<TemporaryRecoveryEntry> confirmedOwners(
    List<TemporaryRecoveryEntry> local,
    List<Map<String, dynamic>> server,
    DateTime now,
  ) {
    final confirmed = <String, DateTime>{};
    for (final record in server) {
      final id = record['sessionId'];
      final role = record['role'];
      final rawExpiration = record['expiresAt'];
      if (id is! String || role != 'owner' ||
          rawExpiration is! String ||
          !RegExp(r'^[a-f0-9]{48}$').hasMatch(id)) continue;
      final expiration = DateTime.tryParse(rawExpiration)?.toUtc();
      if (expiration == null || !expiration.isAfter(now)) continue;
      confirmed[id] = expiration;
    }
    final matched = <TemporaryRecoveryEntry>[];
    final seen = <String>{};
    for (final entry in local) {
      if (entry.role != 'owner' || !entry.validAt(now) ||
          !seen.add(entry.sessionId)) continue;
      final expiration = confirmed[entry.sessionId];
      if (expiration == null) continue;
      // The server is the ultimate authority on expiration.
      matched.add(TemporaryRecoveryEntry(
        sessionId: entry.sessionId,
        role: 'owner',
        expiresAt: expiration,
      ));
    }
    return matched;
  }

  static String encode(List<TemporaryRecoveryEntry> entries, DateTime now) {
    final valid = entries.where((entry) => entry.validAt(now)).toList();
    if (valid.length > 64) throw StateError('Too many temporary sessions');
    if (valid.map((entry) => entry.sessionId).toSet().length != valid.length) {
      throw StateError('Duplicate temporary session');
    }
    return jsonEncode(<String, Object>{
      'version': 1,
      'entries': valid.map((entry) => entry.toJson()).toList(),
    });
  }

  static List<TemporaryRecoveryEntry> decode(String? source, DateTime now) {
    if (source == null || source.isEmpty || source.length > 24000) return const [];
    try {
      final data = jsonDecode(source);
      if (data is! Map || data['version'] != 1 || data['entries'] is! List) {
        return const [];
      }
      final raw = data['entries'] as List;
      if (raw.length > 64) return const [];
      final entries = <TemporaryRecoveryEntry>[];
      final seen = <String>{};
      for (final item in raw) {
        final entry = TemporaryRecoveryEntry.fromJson(item, now);
        if (entry == null) continue;
        if (!seen.add(entry.sessionId)) return const [];
        entries.add(entry);
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }
}

/// Account-bound secure storage. It intentionally does not send a rejoin or
/// register a chat in the UI; the server must authorize that separately.
class TemporaryRecoveryStore {
  TemporaryRecoveryStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static String keyForAccount(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty || id.length > 256) {
      throw const FormatException('Missing account identity');
    }
    return 'fenyvo_trust_recovery_v1.${base64Url.encode(utf8.encode(id))}';
  }

  Future<List<TemporaryRecoveryEntry>> read(String accountId) async {
    final encoded = await _storage.read(key: keyForAccount(accountId));
    return TemporaryRecoveryCodec.decode(encoded, DateTime.now().toUtc());
  }

  Future<void> save(String accountId, List<TemporaryRecoveryEntry> entries) async {
    final now = DateTime.now().toUtc();
    final encoded = TemporaryRecoveryCodec.encode(entries, now);
    await _storage.write(key: keyForAccount(accountId), value: encoded);
  }

  Future<void> upsert(String accountId, TemporaryRecoveryEntry entry) async {
    final now = DateTime.now().toUtc();
    if (!entry.validAt(now)) throw const FormatException('Invalid recovery metadata');
    final current = <TemporaryRecoveryEntry>[...await read(accountId)];
    current.removeWhere((item) => item.sessionId == entry.sessionId);
    current.add(entry);
    await save(accountId, current);
  }

  Future<void> remove(String accountId, String sessionId) async {
    final current = <TemporaryRecoveryEntry>[...await read(accountId)];
    current.removeWhere((entry) => entry.sessionId == sessionId);
    await save(accountId, current);
  }

  Future<void> clearAccount(String accountId) =>
      _storage.delete(key: keyForAccount(accountId));
}
