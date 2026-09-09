import 'package:minime_core/core/services/secure_storage/secure_storage_backend.dart';
import 'package:minime_core/core/services/secure_storage/secure_storage_service.dart';

/// 内存假后端（不依赖任何平台插件）。
///
/// 抽到 helpers 下是为了让 PR-1（存储层）与 PR-2（迁移层）的测试共用同一份桩，
/// 避免各写一份导致行为漂移。
class FakeBackend implements SecureStorageBackend {
  FakeBackend({
    this.id = 'fake',
    this.degraded = false,
    this.failOnRead = false,
    this.failOnWrite = false,
  });

  final Map<String, String> store = <String, String>{};
  final bool failOnRead;
  final bool failOnWrite;

  @override
  final String id;

  @override
  final bool degraded;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read(String key) async {
    if (failOnRead) throw StateError('backend read boom');
    return store[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failOnWrite) throw StateError('backend write boom');
    store[key] = value;
  }

  @override
  Future<void> delete(String key) async => store.remove(key);

  @override
  Future<bool> contains(String key) async => store.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(store);
}

/// 用 [backend] 组装一个 [SecureStorageService]；
/// 传入 [errorSink] 时会收集所有脱敏后的上报消息，供断言使用。
SecureStorageService buildService(
  SecureStorageBackend backend, {
  List<String>? errorSink,
}) {
  final registry = SecureStorageRegistry()..register(backend, asDefault: true);
  return SecureStorageService(
    registry,
    onError: errorSink == null
        ? null
        : (String message, Object? error, StackTrace? stack) {
            errorSink.add(message);
          },
  );
}
