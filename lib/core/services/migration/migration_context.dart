import 'package:shared_preferences/shared_preferences.dart';

import '../secure_storage/secure_storage_service.dart';

/// 迁移执行上下文：一次迁移过程中所有步骤共享的入口。
///
/// 只暴露「读 prefs / 读写安全存储 / 打日志 / 打完成标记」四件事，
/// 步骤本身不接触平台 API，便于单测（测试里可用
/// `SharedPreferences.setMockInitialValues` 与内存后端替换）。
class MigrationContext {
  MigrationContext({
    required this.prefs,
    required this.secureStorage,
    this.log,
  });

  final SharedPreferences prefs;

  /// 凭证的目的地。
  final SecureStorageService secureStorage;

  /// 日志回调：`(level, message, error, stack)`。
  /// level 取 'i' / 'w' / 'e'。调用方负责接到 Logger。
  final void Function(String level, String message,
      [Object? error, StackTrace? stack])? log;

  // ------------------------------------------------------------------ 完成标记

  static const String _markPrefix = 'migration_done_';

  String markKey(String id) => '$_markPrefix$id';

  /// 该步骤是否已完成过（幂等判定依据）。
  bool isDone(String id) => prefs.getBool(markKey(id)) ?? false;

  Future<void> markDone(String id) => prefs.setBool(markKey(id), true);

  // ---------------------------------------------------------------------- 日志

  void info(String msg) => log?.call('i', msg);
  void warn(String msg, [Object? e, StackTrace? s]) =>
      log?.call('w', msg, e, s);
  void error(String msg, [Object? e, StackTrace? s]) =>
      log?.call('e', msg, e, s);
}
