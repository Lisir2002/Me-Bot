import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_backend.dart';

/// Web 端默认后端工厂（bootstrap 条件导入用）。
SecureStorageBackend createDefaultBackend() => SecureStorageWebBackend();

/// Web 端**降级**实现。
///
/// 浏览器无 Keychain/Keystore 等价物，本实现退化为 localStorage
/// （SharedPreferences），**并非真正的加密存储**：同源脚本可读取。
///
/// 因此 [degraded] 恒为 true，bootstrap 初始化时会触发一次告警回调，
/// UI 侧（PR-5 安全体检）应据此向用户明示风险。
class SecureStorageWebBackend implements SecureStorageBackend {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  String get id => 'web_local_storage';

  @override
  bool get degraded => true;

  @override
  Future<bool> isAvailable() async {
    try {
      await _store;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read(String key) async => (await _store).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _store).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _store).remove(key);

  @override
  Future<bool> contains(String key) async => (await _store).containsKey(key);

  @override
  Future<Map<String, String>> readAll() async {
    final prefs = await _store;
    final keys = prefs.getKeys();
    final result = <String, String>{};
    for (final key in keys) {
      final value = prefs.getString(key);
      if (value != null) result[key] = value;
    }
    return result;
  }
}
