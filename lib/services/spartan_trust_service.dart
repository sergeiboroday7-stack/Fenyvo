import 'package:shared_preferences/shared_preferences.dart';

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
}
