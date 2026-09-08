import 'package:shared_preferences/shared_preferences.dart';

import 'socket_service.dart';

/// Local trust decisions for a contact. No message text or contact data leave
/// the device; this is intentionally separate from server-side account state.
class SpartanTrustService {
  SpartanTrustService._();

  static const _trustedPrefix = 'spartan_trust_trusted_';
  static const _blockedPrefix = 'spartan_trust_blocked_';
  static const _reportedPrefix = 'spartan_trust_reported_';

  static String _key(String prefix, String contact) =>
      '$prefix${contact.trim().toLowerCase()}';

  static Future<bool> isTrusted(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(_trustedPrefix, contact)) ?? false;
  }

  static Future<bool> isBlocked(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(_blockedPrefix, contact)) ?? false;
  }

  static Future<bool> isReported(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(_reportedPrefix, contact)) ?? false;
  }

  static Future<String> reportReason(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_key(_reportedPrefix, contact)}_reason') ?? '';
  }

  static Future<void> setTrusted(String contact, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_trustedPrefix, contact), value);
  }

  static Future<void> setBlocked(String contact, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_blockedPrefix, contact), value);
  }

  static Future<void> report(String contact, {String reason = 'Другое'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_reportedPrefix, contact), true);
    await prefs.setString('${_key(_reportedPrefix, contact)}_reason', reason);
  }

  static Future<void> applyRemote(
    String contact, {
    required bool trusted,
    required bool blocked,
    required bool reported,
    String reportReason = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_trustedPrefix, contact), trusted);
    await prefs.setBool(_key(_blockedPrefix, contact), blocked);
    await prefs.setBool(_key(_reportedPrefix, contact), reported);
    final reasonKey = '${_key(_reportedPrefix, contact)}_reason';
    if (reported && reportReason.trim().isNotEmpty) {
      await prefs.setString(reasonKey, reportReason.trim());
    } else {
      await prefs.remove(reasonKey);
    }
  }

  /// Sends only the trust decision metadata to the authenticated server.
  /// Local persistence remains the source of truth while offline.
  static void sync(String contact) {
    final user = contact.trim();
    if (user.isEmpty || !SocketService.instance.isAuthenticated) return;
    Future.wait<dynamic>([
      isTrusted(user),
      isBlocked(user),
      isReported(user),
      reportReason(user),
    ]).then((values) {
      SocketService.instance.sendPulse('trust_update', {
        'contact': user,
        'trusted': values[0],
        'blocked': values[1],
        'reported': values[2],
        'reportReason': values[3],
      });
    });
  }

  static void requestRemote(String contact) {
    final user = contact.trim();
    if (user.isEmpty || !SocketService.instance.isAuthenticated) return;
    SocketService.instance.sendPulse('get_trust_state', {'contact': user});
  }
}
