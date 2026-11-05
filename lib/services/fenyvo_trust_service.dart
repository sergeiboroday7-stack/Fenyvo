import 'package:shared_preferences/shared_preferences.dart';

import 'socket_service.dart';
import 'trust_account_scope.dart';

/// Local trust decisions scoped to the authenticated account.
///
/// Legacy unscoped preferences are intentionally not read or deleted:
/// they cannot safely be attributed to one owner on a shared device.
class FenyvoTrustService {
  FenyvoTrustService._();

  static const _trustedPrefix = 'spartan_trust_trusted_';
  static const _blockedPrefix = 'spartan_trust_blocked_';
  static const _reportedPrefix = 'spartan_trust_reported_';
  static const _explanationSeenKey = 'spartan_trust_explanation_seen';

  static String _owner(String? owner) =>
      (owner ?? SocketService.instance.currentUser ?? '').trim();

  static String? _key(String prefix, String contact, String? owner) =>
      TrustAccountScope.key(
        owner: _owner(owner),
        contact: contact,
        prefix: prefix,
      );

  static Future<bool> isTrusted(String contact, {String? owner}) async {
    final key = _key(_trustedPrefix, contact, owner);
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<bool> isBlocked(String contact, {String? owner}) async {
    final key = _key(_blockedPrefix, contact, owner);
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<bool> isReported(String contact, {String? owner}) async {
    final key = _key(_reportedPrefix, contact, owner);
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<String> reportReason(String contact, {String? owner}) async {
    final key = _key(_reportedPrefix, contact, owner);
    if (key == null) return '';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${key}_reason') ?? '';
  }

  static Future<bool> shouldShowExplanation() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_explanationSeenKey) ?? false);
  }

  static Future<void> markExplanationSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_explanationSeenKey, true);
  }

  static Future<void> setTrusted(
    String contact,
    bool value, {
    String? owner,
  }) async {
    final key = _key(_trustedPrefix, contact, owner);
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<void> setBlocked(
    String contact,
    bool value, {
    String? owner,
  }) async {
    final key = _key(_blockedPrefix, contact, owner);
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<void> report(
    String contact, {
    String reason = 'Другое',
    String? owner,
  }) async {
    final key = _key(_reportedPrefix, contact, owner);
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    await prefs.setString('${key}_reason', reason);
  }

  static Future<void> applyRemote(
    String contact, {
    required bool trusted,
    required bool blocked,
    required bool reported,
    String reportReason = '',
    String? owner,
  }) async {
    // Capture the account before awaiting SharedPreferences.
    final identity = _owner(owner);
    final trustedKey = _key(_trustedPrefix, contact, identity);
    final blockedKey = _key(_blockedPrefix, contact, identity);
    final reportedKey = _key(_reportedPrefix, contact, identity);

    if (trustedKey == null || blockedKey == null || reportedKey == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(trustedKey, trusted);
    await prefs.setBool(blockedKey, blocked);
    await prefs.setBool(reportedKey, reported);

    final reasonKey = '${reportedKey}_reason';
    if (reported && reportReason.trim().isNotEmpty) {
      await prefs.setString(reasonKey, reportReason.trim());
    } else {
      await prefs.remove(reasonKey);
    }
  }

  /// Send only the active owner's trust metadata.
  static void sync(String contact) {
    final identity = _owner(null);
    final peer = contact.trim();

    if (identity.isEmpty ||
        peer.isEmpty ||
        identity.toLowerCase() == peer.toLowerCase() ||
        !SocketService.instance.isAuthenticated) {
      return;
    }

    Future.wait<dynamic>([
      isTrusted(peer, owner: identity),
      isBlocked(peer, owner: identity),
      isReported(peer, owner: identity),
      reportReason(peer, owner: identity),
    ]).then((values) {
      if (!SocketService.instance.isAuthenticated || _owner(null) != identity) {
        return;
      }

      SocketService.instance.sendPulse('trust_update', {
        'contact': peer,
        'trusted': values[0],
        'blocked': values[1],
        'reported': values[2],
        'reportReason': values[3],
      });
    });
  }

  static void requestRemote(String contact) {
    final identity = _owner(null);
    final peer = contact.trim();

    if (identity.isEmpty ||
        peer.isEmpty ||
        identity.toLowerCase() == peer.toLowerCase() ||
        !SocketService.instance.isAuthenticated) {
      return;
    }

    SocketService.instance.sendPulse('get_trust_state', {'contact': peer});
  }
}
