import 'migration_context.dart';
import 'migration_step.dart';

/// 版本化迁移注册表（预留接口④）。
///
/// 未来「存储层演进」（Hive → Isar）、「新增凭证类型」等需要搬数据的改造，
/// 都登记成一个 [MigrationStep] 即可复用同一套执行 / 回滚 / 续跑框架，
/// 而不必再写一次性的 `if (version < N)` 分支。
///
/// 行为约定：
/// - 按 [MigrationStep.version] 升序执行，同版本按注册顺序；
/// - 单步抛异常 → 记 `failed` 并**继续**后续步骤（fail-open，不阻塞启动）；
/// - 已完成（有标记）的步骤自动跳过。
class MigrationRunner {
  final List<MigrationStep> _steps = <MigrationStep>[];

  /// 注册一个步骤。重复 id 会被忽略（保留先注册者）。
  void register(MigrationStep step) {
    if (_steps.any((s) => s.id == step.id)) return;
    _steps.add(step);
  }

  /// 已注册步骤（按执行顺序的快照）。
  List<MigrationStep> get steps {
    final sorted = List<MigrationStep>.of(_steps)
      ..sort((a, b) {
        final c = a.version.compareTo(b.version);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return List.unmodifiable(sorted);
  }

  /// 依次执行所有需要执行的步骤。
  Future<MigrationReport> run(MigrationContext ctx) async {
    final results = <MigrationStepResult>[];
    for (final step in steps) {
      final bool needs;
      try {
        needs = await step.shouldRun(ctx);
      } catch (e, s) {
        ctx.error('migration.shouldRun failed [${step.id}]', e, s);
        results.add(MigrationStepResult(
          id: step.id,
          version: step.version,
          status: 'failed',
          error: e,
          stack: s,
        ));
        continue;
      }
      if (!needs) {
        results.add(MigrationStepResult(
          id: step.id,
          version: step.version,
          status: 'skipped',
        ));
        continue;
      }
      try {
        await step.run(ctx);
        await ctx.markDone(step.id);
        ctx.info('migration applied [${step.id}] v${step.version}');
        results.add(MigrationStepResult(
          id: step.id,
          version: step.version,
          status: 'applied',
        ));
      } catch (e, s) {
        ctx.error('migration failed [${step.id}] v${step.version}', e, s);
        results.add(MigrationStepResult(
          id: step.id,
          version: step.version,
          status: 'failed',
          error: e,
          stack: s,
        ));
      }
    }
    return MigrationReport(results);
  }
}
