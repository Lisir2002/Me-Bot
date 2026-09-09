import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_backend.dart';

/// 移动 / 桌面端默认后端工厂（bootstrap 条件导入用）。
SecureStorageBackend createDefaultBackend() => SecureStorageIoBackend();

/// 基于 `flutter_secure_storage` 的后端实现。
///
/// 平台后端：Android Keystore（EncryptedSharedPreferences）、iOS/macOS Keychain、
/// Windows 凭据管理器（DPAPI）、Linux libsecret（无 keyring 时由上层降级处理）。
class SecureStorageIoBackend implements SecureStorageBackend {
  SecureStorageIoBackend({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: const AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
              iOptions: const IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  String get id => 'io_secure_storage';

  @override
  bool get degraded => false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> contains(String key) => _storage.containsKey(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
