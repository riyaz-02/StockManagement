import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the mobile/password pair used by the biometric login shortcut.
/// Backed by flutter_secure_storage (Android Keystore / iOS Keychain), kept
/// separate from StorageService's plain SharedPreferences since this holds
/// an actual password. The "prompt dismissed" flag lives in SharedPreferences
/// (non-sensitive) so we don't nag a user who already said no.
class SecureCredentialStorage {
  static const _keyMobile = 'biometric_login_mobile';
  static const _keyPassword = 'biometric_login_password';
  static const _keyPromptDismissed = 'biometric_prompt_dismissed';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveCredentials(String mobile, String password) async {
    await _secureStorage.write(key: _keyMobile, value: mobile);
    await _secureStorage.write(key: _keyPassword, value: password);
  }

  Future<Map<String, String>?> getCredentials() async {
    final mobile = await _secureStorage.read(key: _keyMobile);
    final password = await _secureStorage.read(key: _keyPassword);
    if (mobile == null || password == null) return null;
    return {'mobile': mobile, 'password': password};
  }

  Future<bool> hasCredentials() async {
    final mobile = await _secureStorage.read(key: _keyMobile);
    return mobile != null;
  }

  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _keyMobile);
    await _secureStorage.delete(key: _keyPassword);
  }

  Future<bool> wasPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPromptDismissed) ?? false;
  }

  Future<void> setPromptDismissed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPromptDismissed, value);
  }
}
