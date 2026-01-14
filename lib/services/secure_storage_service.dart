import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service for securely storing sensitive data like passwords and tokens.
/// Uses platform-specific secure storage (Keychain on iOS, EncryptedSharedPreferences on Android).
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Keys for secure storage
  static const String _keyAuthToken = 'secure_auth_token';
  static const String _keyMaAuthToken = 'secure_ma_auth_token';
  static const String _keyAuthCredentials = 'secure_auth_credentials';
  static const String _keyPassword = 'secure_password';
  static const String _keyAbsApiToken = 'secure_abs_api_token';

  // Auth Token (for stream requests)
  static Future<String?> getAuthToken() async {
    return await _storage.read(key: _keyAuthToken);
  }

  static Future<void> setAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _keyAuthToken);
    } else {
      await _storage.write(key: _keyAuthToken, value: token);
    }
  }

  // Music Assistant Native Auth Token (long-lived token)
  static Future<String?> getMaAuthToken() async {
    return await _storage.read(key: _keyMaAuthToken);
  }

  static Future<void> setMaAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _keyMaAuthToken);
    } else {
      await _storage.write(key: _keyMaAuthToken, value: token);
    }
  }

  static Future<void> clearMaAuthToken() async {
    await _storage.delete(key: _keyMaAuthToken);
  }

  // Auth Credentials (serialized auth strategy credentials)
  static Future<Map<String, dynamic>?> getAuthCredentials() async {
    final json = await _storage.read(key: _keyAuthCredentials);
    if (json == null) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  static Future<void> setAuthCredentials(Map<String, dynamic> credentials) async {
    await _storage.write(key: _keyAuthCredentials, value: jsonEncode(credentials));
  }

  static Future<void> clearAuthCredentials() async {
    await _storage.delete(key: _keyAuthCredentials);
  }

  // Password
  static Future<String?> getPassword() async {
    return await _storage.read(key: _keyPassword);
  }

  static Future<void> setPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _storage.delete(key: _keyPassword);
    } else {
      await _storage.write(key: _keyPassword, value: password);
    }
  }

  // Audiobookshelf API Token
  static Future<String?> getAbsApiToken() async {
    return await _storage.read(key: _keyAbsApiToken);
  }

  static Future<void> setAbsApiToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _keyAbsApiToken);
    } else {
      await _storage.write(key: _keyAbsApiToken, value: token);
    }
  }

  /// Clear all secure storage (used during logout)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // Migration completed flag key
  static const String _keyMigrationCompleted = 'secure_storage_migration_completed';

  /// Migrate credentials from SharedPreferences to secure storage.
  /// Call this once during app upgrade to migrate existing users.
  /// Uses a flag to skip migration on subsequent runs for performance.
  static Future<void> migrateFromSharedPreferences() async {
    // Import SharedPreferences for migration
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Skip if migration already completed
    if (prefs.getBool(_keyMigrationCompleted) == true) {
      return;
    }

    // Migrate auth token
    final authToken = prefs.getString('auth_token');
    if (authToken != null && authToken.isNotEmpty) {
      await setAuthToken(authToken);
      await prefs.remove('auth_token');
    }

    // Migrate MA auth token
    final maAuthToken = prefs.getString('ma_auth_token');
    if (maAuthToken != null && maAuthToken.isNotEmpty) {
      await setMaAuthToken(maAuthToken);
      await prefs.remove('ma_auth_token');
    }

    // Migrate auth credentials
    final authCredentials = prefs.getString('auth_credentials');
    if (authCredentials != null && authCredentials.isNotEmpty) {
      try {
        final decoded = jsonDecode(authCredentials) as Map<String, dynamic>;
        await setAuthCredentials(decoded);
        await prefs.remove('auth_credentials');
      } catch (_) {
        // Invalid JSON, just remove it
        await prefs.remove('auth_credentials');
      }
    }

    // Migrate password
    final password = prefs.getString('password');
    if (password != null && password.isNotEmpty) {
      await setPassword(password);
      await prefs.remove('password');
    }

    // Migrate ABS API token
    final absApiToken = prefs.getString('abs_api_token');
    if (absApiToken != null && absApiToken.isNotEmpty) {
      await setAbsApiToken(absApiToken);
      await prefs.remove('abs_api_token');
    }

    // Mark migration as completed to skip on future runs
    await prefs.setBool(_keyMigrationCompleted, true);
  }
}
