import 'credential_record.dart';
import 'secure_storage_backend.dart';

/// 应用访问安全存储的统一入口。
///
/// 设计要点：
/// - 通过 [SecureStorageRegistry] 在运行期解析后端，新后端注册后即刻生效（预留接口②）；
/// - **any error path 均不携带凭证值**：日志/异常只出现操作名与 key；
/// - 错误上报通过 [onError] 回调注入（PR-2 接线到既有 `Logger`），
///   使本模块在 PR-1 阶段保持零业务依赖、可独立测试。
class SecureStorageService {
  SecureStorageService(
    this._registry, {
    this.onError,
  });

  final SecureStorageRegistry _registry;

  /// 错误上报回调：`(message, error, stack)`。
  /// message 已脱敏，可安全写日志。
  final void Function(String message, Object? error, StackTrace? stack)?
      onError;

  /// 当前生效的后端。
  SecureStorageBackend get backend {
    final b = _registry.defaultBackend;
    if (b == null) {
      throw const SecureStorageException(
        'no secure storage backend registered; call SecureStorage.init() first',
      );
    }
    return b;
  }

  /// 是否运行在降级实现上（UI 可据此提示）。
  bool get isDegraded => _registry.defaultBackend?.degraded ?? false;

  // ---------------------------------------------------------------- 基础读写

  /// 读取；后端异常时返回 null 并上报（fail-soft，不阻塞启动）。
  Future<String?> read(String key) => _guard<String?>(
        key,
        'read',
        () => backend.read(key),
        failSoft: true,
      );

  /// 写入；失败时抛 [SecureStorageException]（凭证必须确认落盘）。
  Future<void> write(String key, String value) =>
      _guard<void>(key, 'write', () => backend.write(key, value));

  /// 删除；失败时抛 [SecureStorageException]。
  Future<void> delete(String key) =>
      _guard<void>(key, 'delete', () => backend.delete(key));

  Future<bool> contains(String key) => _guard<bool>(
        key,
        'contains',
        () => backend.contains(key),
        failSoft: true,
        fallback: false,
      );

  /// 全量读取（迁移器 / PR-5 安全体检专用）。
  Future<Map<String, String>> readAll() => _guard<Map<String, String>>(
        '*',
        'readAll',
        () => backend.readAll(),
        failSoft: true,
        fallback: <String, String>{},
      );

  // ------------------------------------------------------------ 类型化凭证

  /// 读取类型化凭证记录（预留接口①）。
  Future<CredentialRecord?> readCredential(String key) async {
    final raw = await read(key);
    return CredentialRecord.decode(raw);
  }

  /// 写入类型化凭证记录。
  Future<void> writeCredential(String key, CredentialRecord record) {
    return write(key, record.encode());
  }

  /// 记录一次使用（写回 lastUsedAt），凭证不存在时静默返回。
  Future<void> touchCredential(String key) async {
    final record = await readCredential(key);
    if (record == null) return;
    await writeCredential(key, record.touch());
  }

  // ------------------------------------------------------------------ 内部

  /// [failSoft] 为 true 时出错返回 [fallback]（可为 null）而不抛出；
  /// 为 false（默认）时抛 [SecureStorageException]，用于必须确认落盘的写操作。
  Future<T> _guard<T>(
    String key,
    String op,
    Future<T> Function() action, {
    bool failSoft = false,
    T? fallback,
  }) async {
    try {
      return await action();
    } catch (e, s) {
      // 只记录操作名与 key，绝不记录 value
      onError?.call(
        'secure_storage.$op failed'
        '${failSoft ? ' (fail-soft)' : ''} [key=$key]',
        e,
        s,
      );
      if (failSoft) return fallback as T;
      throw SecureStorageException(
        'secure_storage.$op failed [key=$key]',
        cause: e,
      );
    }
  }
}
