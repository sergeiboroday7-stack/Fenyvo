import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the saved login password in the platform-protected credential store.
///
/// Older FENYVO builds used SharedPreferences. Migration is deliberately
/// ordered as secure write -> legacy delete so an interrupted upgrade cannot
/// silently lose the user's saved login.
class CredentialStorageService {
  CredentialStorageService._();

  static final CredentialStorageService instance = CredentialStorageService._();

  static const String _securePasswordKey = 'spartan.login_password.v1';
  static const String _legacyPasswordKey = 'password';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> readPassword(SharedPreferences preferences) async {
    try {
      final securePassword = await _storage.read(key: _securePasswordKey);
      if (securePassword != null && securePassword.isNotEmpty) {
        await preferences.remove(_legacyPasswordKey);
        return securePassword;
      }
    } catch (_) {
      // A legacy password is still usable when secure storage is temporarily
      // unavailable. It must not be deleted until a secure write succeeds.
    }

    final legacyPassword = preferences.getString(_legacyPasswordKey);
    if (legacyPassword == null || legacyPassword.isEmpty) return null;

    try {
      await _storage.write(key: _securePasswordKey, value: legacyPassword);
      await preferences.remove(_legacyPasswordKey);
    } catch (_) {
      // Keep the old value for one more launch instead of logging the user out.
    }

    return legacyPassword;
  }

  Future<void> savePassword(
    String password,
    SharedPreferences preferences,
  ) async {
    await _storage.write(key: _securePasswordKey, value: password);
    await preferences.remove(_legacyPasswordKey);
  }

  Future<void> clearPassword(SharedPreferences preferences) async {
    await _storage.delete(key: _securePasswordKey);
    await preferences.remove(_legacyPasswordKey);
  }
}
