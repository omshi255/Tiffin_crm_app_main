import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class SecureStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserRole = 'user_role';
  static const _keyUserId = 'user_id';

  // Memory-based cache to fall back on if secure storage writes/reads throw on the platform (e.g. Windows DPAPI issues or Web restrictions)
  static final Map<String, String> _memCache = {};

  static Future<void> saveAccessToken(String token) async {
    _memCache[_keyAccessToken] = token;
    try {
      await _storage.write(key: _keyAccessToken, value: token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to saveAccessToken: $e');
      }
    }
  }

  static Future<String?> getAccessToken() async {
    if (_memCache.containsKey(_keyAccessToken)) {
      return _memCache[_keyAccessToken];
    }
    try {
      final value = await _storage.read(key: _keyAccessToken);
      if (value != null) {
        _memCache[_keyAccessToken] = value;
      }
      return value;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to getAccessToken: $e');
      }
      return null;
    }
  }

  static Future<void> saveRefreshToken(String token) async {
    _memCache[_keyRefreshToken] = token;
    try {
      await _storage.write(key: _keyRefreshToken, value: token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to saveRefreshToken: $e');
      }
    }
  }

  static Future<String?> getRefreshToken() async {
    if (_memCache.containsKey(_keyRefreshToken)) {
      return _memCache[_keyRefreshToken];
    }
    try {
      final value = await _storage.read(key: _keyRefreshToken);
      if (value != null) {
        _memCache[_keyRefreshToken] = value;
      }
      return value;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to getRefreshToken: $e');
      }
      return null;
    }
  }

  static Future<void> saveUserRole(String role) async {
    _memCache[_keyUserRole] = role;
    try {
      await _storage.write(key: _keyUserRole, value: role);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to saveUserRole: $e');
      }
    }
  }

  static Future<String?> getUserRole() async {
    if (_memCache.containsKey(_keyUserRole)) {
      return _memCache[_keyUserRole];
    }
    try {
      final value = await _storage.read(key: _keyUserRole);
      if (value != null) {
        _memCache[_keyUserRole] = value;
      }
      return value;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to getUserRole: $e');
      }
      return null;
    }
  }

  static Future<void> saveUserId(String id) async {
    _memCache[_keyUserId] = id;
    try {
      await _storage.write(key: _keyUserId, value: id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to saveUserId: $e');
      }
    }
  }

  static Future<String?> getUserId() async {
    if (_memCache.containsKey(_keyUserId)) {
      return _memCache[_keyUserId];
    }
    try {
      final value = await _storage.read(key: _keyUserId);
      if (value != null) {
        _memCache[_keyUserId] = value;
      }
      return value;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to getUserId: $e');
      }
      return null;
    }
  }

  static Future<void> set(String key, String value) async {
    _memCache[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to set $key: $e');
      }
    }
  }

  static Future<String?> get(String key) async {
    if (_memCache.containsKey(key)) {
      return _memCache[key];
    }
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        _memCache[key] = value;
      }
      return value;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to get $key: $e');
      }
      return null;
    }
  }

  static Future<void> clearAll() async {
    _memCache.clear();
    try {
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyUserRole);
      await _storage.delete(key: _keyUserId);
      await _storage.delete(key: 'vendorOnboarded');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureStorage] Failed to clearAll: $e');
      }
    }
  }
}
