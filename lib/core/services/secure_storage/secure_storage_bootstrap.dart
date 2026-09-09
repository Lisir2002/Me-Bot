import 'secure_storage_backend.dart';
import 'secure_storage_io.dart' if (dart.library.html) 'secure_storage_web.dart'
    as platform;
import 'secure_storage_service.dart';

/// 安全存储装配入口。
///
/// 使用方式（PR-2 在 `main.dart` 中接线，位于 `Logger.init()` 之后）：
/// ```dart
/// await SecureStorage.init(onError: (msg, e, s) => Logger.w(LogTags.security, msg, e, s));
/// ```
///
/// 未来新后端（鸿蒙 / Isar / 企业 KMS）只需：
/// ```dart
/// SecureStorage.registerBackend(OhosSecureBackend(), asDefault: true);
/// ```
class SecureStorage {
  static SecureStorageService? _service;
  static SecureStorageRegistry? _registry;

  /// 已初始化的实例；未初始化时抛异常（快速失败，避免静默降级到不安全路径）。
  static SecureStorageService get instance {
    final s = _service;
    if (s == null) {
      throw const SecureStorageException(
        'SecureStorage not initialized; call SecureStorage.init() during startup',
      );
    }
    return s;
  }

  static bool get isInitialized => _service != null;

  /// 初始化：装配平台默认后端并注册。
  ///
  /// [backendOverride] 便于测试或企业版注入自定义后端。
  static Future<SecureStorageService> init({
    SecureStorageBackend? backendOverride,
    void Function(String message, Object? error, StackTrace? stack)? onError,
  }) async {
    final registry = SecureStorageRegistry();
    final backend = backendOverride ?? platform.createDefaultBackend();

    registry.register(backend, asDefault: true);

    if (backend.degraded) {
      onError?.call(
        'secure_storage running in DEGRADED mode (backend=${backend.id}); '
        'credentials are NOT hardware-protected on this platform',
        null,
        null,
      );
    }

    _registry = registry;
    final service = SecureStorageService(registry, onError: onError);
    _service = service;
    return service;
  }

  /// 运行期注册新后端（预留接口②）。
  static void registerBackend(
    SecureStorageBackend backend, {
    bool asDefault = false,
  }) {
    _registry?.register(backend, asDefault: asDefault);
  }

  /// 仅测试使用：清空全局状态。
  static void resetForTest() {
    _service = null;
    _registry = null;
  }
}
