import 'migration_context.dart';

/// 一个可注册的迁移步骤（预留接口④）。
///
/// 约定：
/// - **幂等**：同一步骤重复执行结果一致，可安全中断续跑；
/// - **fail-open**：允许抛异常，[MigrationRunner] 会捕获并继续后续步骤；
/// - 步骤内若搬移数据，采用「先写新位置 → 确认成功 → 再清旧位置」两阶段，
///   任意时刻中断都不会丢数据。
abstract class MigrationStep {
  /// 全局唯一标识，用于完成标记。
  String get id;

  /// 目标版本号，用于排序（升序执行）。
  int get version;

  /// 是否仍需执行。默认按完成标记判定。
  Future<bool> shouldRun(MigrationContext ctx) async => !ctx.isDone(id);

  Future<void> run(MigrationContext ctx);
}

/// 单个步骤的执行结果。
class MigrationStepResult {
  const MigrationStepResult({
    required this.id,
    required this.version,
    required this.status,
    this.error,
    this.stack,
  });

  final String id;
  final int version;

  /// `applied` 已执行 / `skipped` 跳过 / `failed` 失败。
  final String status;
  final Object? error;
  final StackTrace? stack;

  bool get ok => status != 'failed';

  @override
  String toString() => 'MigrationStepResult($id v$version: $status)';
}

/// 一次迁移运行的汇总。
class MigrationReport {
  MigrationReport(this.results);

  final List<MigrationStepResult> results;

  bool get ok => results.every((r) => r.ok);

  int get applied => results.where((r) => r.status == 'applied').length;
  int get skipped => results.where((r) => r.status == 'skipped').length;
  int get failed => results.where((r) => r.status == 'failed').length;

  @override
  String toString() =>
      'MigrationReport(applied=$applied, skipped=$skipped, failed=$failed)';
}
