/// 安全体检：插件化扫描引擎的契约层（预留接口③）。
///
/// 体检引擎 [SecurityCheckupService] 只负责「注册扫描器 → 聚合报告 → 按需 autoFix」，
/// 具体扫描逻辑分散到各个 [CheckupScanner] 实现里。未来要加新扫描器
/// （debugPrint 残留、依赖漏洞、备份文件深扫……）只需实现本接口并注册即可，
/// 引擎与已有扫描器零改动。
///
/// 约束（与方案「五扇门」对齐）：接口只收口在边界，每个扩展点必须有 ≥1 个真实实现与单测。

/// 体检发现项严重度。
enum CheckupSeverity {
  /// 🟢 通过：无需处理。
  safe,

  /// 🟡 存疑：可能但不一定有问题，给出提示而非直接判密钥。
  warn,

  /// 🔴 明文残留 / 高危：应当处理。
  danger;

  bool get isProblem => this != CheckupSeverity.safe;

  int get rank => switch (this) {
        CheckupSeverity.safe => 0,
        CheckupSeverity.warn => 1,
        CheckupSeverity.danger => 2,
      };

  static CheckupSeverity max(CheckupSeverity a, CheckupSeverity b) =>
      a.rank >= b.rank ? a : b;
}

/// 单条体检发现。
///
/// 注意：发现项**绝不携带凭证明文值**，detail 里只描述「哪个 key / 什么模式」，
/// 具体值不出现在任何日志或报告文本中。
class CheckupFinding {
  const CheckupFinding({
    required this.id,
    required this.scannerId,
    required this.title,
    required this.detail,
    required this.severity,
    this.autoFixable = false,
    this.fixHint,
  });

  /// 全局唯一 id（scannerId + 业务键），便于 autoFix 精确匹配。
  final String id;

  /// 来源扫描器 id。
  final String scannerId;

  final String title;

  /// 人类可读的说明（已脱敏，不出现凭证值）。
  final String detail;

  final CheckupSeverity severity;

  /// 是否支持一键修复（引擎据此决定是否展示「修复」按钮）。
  final bool autoFixable;

  /// 修复按钮文案 / 提示。
  final String? fixHint;

  CheckupFinding copyWith({
    CheckupSeverity? severity,
    String? detail,
    bool? autoFixable,
  }) =>
      CheckupFinding(
        id: id,
        scannerId: scannerId,
        title: title,
        detail: detail ?? this.detail,
        severity: severity ?? this.severity,
        autoFixable: autoFixable ?? this.autoFixable,
        fixHint: fixHint,
      );
}

/// 一次体检的聚合报告。
class CheckupReport {
  const CheckupReport({
    required this.findings,
    required this.scannedAt,
  });

  final List<CheckupFinding> findings;
  final DateTime scannedAt;

  CheckupSeverity get overallSeverity => findings.fold(
        CheckupSeverity.safe,
        (acc, f) => CheckupSeverity.max(acc, f.severity),
      );

  List<CheckupFinding> bySeverity(CheckupSeverity s) =>
      findings.where((f) => f.severity == s).toList();

  int get dangerCount => bySeverity(CheckupSeverity.danger).length;
  int get warnCount => bySeverity(CheckupSeverity.warn).length;
  int get safeCount => bySeverity(CheckupSeverity.safe).length;

  bool get hasProblem => findings.any((f) => f.severity.isProblem);

  /// 可一键修复的发现项。
  List<CheckupFinding> get fixable =>
      findings.where((f) => f.autoFixable).toList();

  CheckupReport copyWith({List<CheckupFinding>? findings}) => CheckupReport(
        findings: findings ?? this.findings,
        scannedAt: scannedAt,
      );
}

/// 安全体检扫描器插件契约（预留接口③）。
///
/// 实现要点：
/// - [scan] 只读、幂等、不抛异常（内部错误由引擎兜底为一条 warn）；
/// - [autoFix] 只对**安全可逆**的操作开放（如删除已确认孤儿、清理应删的旧明文 key），
///   不可逆或可能影响用户数据的操作返回 false，引擎只展示提示。
abstract class CheckupScanner {
  const CheckupScanner();

  /// 扫描器唯一 id（用于报告归因与去重）。
  String get id;

  /// 扫描器标题（展示用）。
  String get title;

  /// 该扫描器所属类别的基准严重度（用于 UI 图标着色）。
  CheckupSeverity get severity;

  /// 执行扫描，返回本扫描器发现的全部问题（可空，引擎会合并）。
  Future<List<CheckupFinding>> scan();

  /// 对单条发现执行一键修复；成功返回 true，不支持/失败返回 false。
  /// 默认不支持（多数扫描器只做检测 + 提示）。
  Future<bool> autoFix(CheckupFinding finding) async => false;
}
