/// 安全存储后端接口（预留接口②）。
///
/// 新平台 / 新实现（鸿蒙端、Isar 加密 box、企业 KMS）只需实现本接口并在启动时
/// 注册到 [SecureStorageRegistry]，核心代码零改动。
abstract class SecureStorageBackend {
  /// 后端唯一标识（用于注册与诊断展示）。
  String get id;

  /// 是否为「降级」实现（如 Web 端 localStorage）。
  /// 为 true 时上层应提示用户凭证保护强度有限。
  bool get degraded => false;

  /// 后端在当前平台是否可用（不可用时注册器会回退其它实现）。
  Future<bool> isAvailable();

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<bool> contains(String key);

  /// 全量读取，仅迁移器与诊断（PR-5 安全体检）使用。
  Future<Map<String, String>> readAll();
}

/// 安全存储异常。
///
/// ⚠️ message 中**绝不包含**凭证值，可安全写入日志。
class SecureStorageException implements Exception {
  const SecureStorageException(this.message, {this.cause});

  final String message;

  /// 原始异常，仅用于内存调试，不得序列化或打印其 message 之外的凭证内容。
  final Object? cause;

  @override
  String toString() => 'SecureStorageException: $message';
}

/// 后端注册器（预留接口②）。
///
/// - 启动时由 bootstrap 装配默认实现；
/// - 后续新后端（插件 / 平台适配 / 企业后端）可在任意时刻注册并切换为默认。
class SecureStorageRegistry {
  final Map<String, SecureStorageBackend> _backends =
      <String, SecureStorageBackend>{};

  String? _defaultId;

  /// 注册后端；[asDefault] 为 true 时设为默认实现。
  void register(
    SecureStorageBackend backend, {
    bool asDefault = false,
  }) {
    _backends[backend.id] = backend;
    if (asDefault || _defaultId == null) {
      _defaultId = backend.id;
    }
  }

  /// 按 id 取后端。
  SecureStorageBackend? get(String id) => _backends[id];

  /// 当前默认后端（未注册任何后端时为 null）。
  SecureStorageBackend? get defaultBackend =>
      _defaultId == null ? null : _backends[_defaultId];

  /// 是否存在默认后端。
  bool get hasBackend => defaultBackend != null;

  /// 已注册后端 id（诊断用）。
  List<String> get backendIds => _backends.keys.toList(growable: false);
}
