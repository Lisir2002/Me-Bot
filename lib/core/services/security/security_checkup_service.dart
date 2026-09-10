import '../logging/logger.dart';
import '../logging/log_tags.dart';
import 'checkup_scanner.dart';

/// 安全体检引擎（PR-5）。
///
/// 只做三件事：**注册扫描器 → 聚合报告 → 按需 autoFix**。具体检测逻辑全在
/// [CheckupScanner] 实现里，引擎本身零业务知识，符合「五扇门」中预留接口③的定位。
///
/// 用法：
/// ```dart
/// final svc = SecurityCheckupService([LegacyPrefsScanner(prefs), ...]);
/// final report = await svc.run();          // 一键体检
/// await svc.fix(report.fixable);           // 一键修复可修项
/// ```
class SecurityCheckupService {
  SecurityCheckupService([List<CheckupScanner>? scanners])
      : _scanners = List.of(scanners ?? const []);

  final List<CheckupScanner> _scanners;

  /// 当前注册的扫描器（不可变视图）。
  List<CheckupScanner> get scanners => List.unmodifiable(_scanners);

  /// 注册一个扫描器（运行期可动态加新扫描器）。
  void register(CheckupScanner scanner) {
    if (_scanners.any((s) => s.id == scanner.id)) return;
    _scanners.add(scanner);
  }

  /// 执行全部扫描器，聚合为一份报告。
  ///
  /// [strings] 为用户可见文案的 l10n 注入入口（展示层传 `L10nCheckupStrings`，
  /// 测试传 Fake）。
  /// 单扫描器抛异常不会拖垮整体：异常被记作一条 warn 发现，并记日志。
  /// 整体扫描超时 10 秒，避免某个扫描器卡死导致页面永远 loading。
  Future<CheckupReport> run(CheckupStrings strings) async {
    final findings = <CheckupFinding>[];
    for (final scanner in _scanners) {
      try {
        final r = await scanner.scan(strings).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                Logger.w(LogTags.security,
                    '[${scanner.id}] scan timed out after 10s, skipped');
                return const [];
              },
            );
        if (r.isNotEmpty) findings.addAll(r);
      } catch (e, s) {
        Logger.w(LogTags.security,
            '[$scanner.id] scan failed, skipped: $e', e, s);
        findings.add(CheckupFinding(
          id: '${scanner.id}:error',
          scannerId: scanner.id,
          title: strings.scannerErrorTitle(scanner.title),
          detail: strings.scannerErrorDetail(),
          severity: CheckupSeverity.warn,
          autoFixable: false,
        ));
      }
    }
    Logger.i(LogTags.security,
        'checkup done: ${findings.length} findings (danger=${findings.where((f) => f.severity == CheckupSeverity.danger).length}, warn=${findings.where((f) => f.severity == CheckupSeverity.warn).length})');
    return CheckupReport(findings: findings, scannedAt: DateTime.now());
  }

  /// 对给定发现项逐个执行 autoFix（跳过不支持的）。
  /// 返回真正修复成功的数量；失败的仍保留在报告中，由 UI 提示。
  Future<int> fix(List<CheckupFinding> findings) async {
    var fixed = 0;
    for (final f in findings) {
      final scanner = _scanners.where((s) => s.id == f.scannerId).firstOrNull;
      if (scanner == null || !f.autoFixable) continue;
      try {
        if (await scanner.autoFix(f)) fixed++;
      } catch (e, s) {
        Logger.w(LogTags.security, '[${f.scannerId}] autoFix failed: $e', e, s);
      }
    }
    return fixed;
  }
}
