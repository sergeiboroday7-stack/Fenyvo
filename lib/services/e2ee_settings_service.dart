import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled E2EE switch.
///
/// This preference is deliberately separate from key material. It is safe to
/// keep here; identities and ratchet state are stored by [SignalSecureStore].
class E2eeSettingsService {
  E2eeSettingsService._();

  static final instance = E2eeSettingsService._();
  static const _enabledKey = 'signal_e2ee_enabled_v2';
  static const _peerKeyPrefix = 'signal_e2ee_active_peers_v1_';
  static const _verifiedKeyPrefix = 'signal_e2ee_verified_v1_';

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }

  String _peerKey(String username) =>
      '$_peerKeyPrefix${username.trim().toLowerCase()}';

  Future<Set<String>> activePeers(String username) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_peerKey(username)) ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<void> setPeerActive(String username, String peer, bool active) async {
    final cleanPeer = peer.trim();
    if (username.trim().isEmpty || cleanPeer.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final peers = await activePeers(username);
    if (active) {
      peers.add(cleanPeer);
    } else {
      peers.remove(cleanPeer);
    }
    final sorted = peers.toList()..sort();
    await preferences.setStringList(_peerKey(username), sorted);
  }

  Future<void> clearActivePeers(String username) async {
    if (username.trim().isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_peerKey(username));
  }

  String _verifiedKey(String username, String peer) =>
      '$_verifiedKeyPrefix${username.trim().toLowerCase()}_${peer.trim().toLowerCase()}';

  Future<bool> isFingerprintVerified(
    String username,
    String peer,
    String fingerprint,
  ) async {
    return await verifiedFingerprint(username, peer) == fingerprint;
  }

  Future<String?> verifiedFingerprint(String username, String peer) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_verifiedKey(username, peer))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setFingerprintVerified(
    String username,
    String peer,
    String fingerprint,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_verifiedKey(username, peer), fingerprint);
  }

  Future<void> clearFingerprintVerification(
    String username,
    String peer,
  ) async {
    if (username.trim().isEmpty || peer.trim().isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_verifiedKey(username, peer));
  }
}
