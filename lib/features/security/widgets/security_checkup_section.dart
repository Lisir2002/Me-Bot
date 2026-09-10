// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';

import '../../../core/services/security/checkup_scanner.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_section_header.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import 'security_shared.dart';

/// 安全体检 section（PR-5 可视化重构）。
///
/// 从 security_page.dart 单文件抽出。职责：
/// - 进页自动扫 + 运行体检按钮（running 时禁用并转圈）；
/// - 一键修复全部（外层弹确认后调用 [onAutoFix]）；
/// - **新功能 2：风险等级聚合**——卡片顶部展示高危/中危/低危数量胶囊，
///   点击胶囊可筛选只看对应等级的 finding（再次点击取消筛选）；
/// - **P0 修复**：单条 finding 的修复按钮只修当前项 [onFixSingle(f)]，
///   不再错误地走「一键修复全部」。
class SecurityCheckupSection extends StatefulWidget {
  const SecurityCheckupSection({
    super.key,
    this.report,
    required this.running,
    required this.onRunCheckup,
    required this.onAutoFix,
    required this.onFixSingle,
  });

  /// 最近一次体检报告；null 表示尚未跑完或无结果。
  final CheckupReport? report;

  /// 体检引擎是否正在运行。
  final bool running;

  /// 点击「运行体检」。
  final Future<void> Function() onRunCheckup;

  /// 点击「一键修复全部」（外层应已弹确认）。
  final Future<void> Function() onAutoFix;

  /// 修复单条 finding（P0：必须只修当前项）。
  final Future<void> Function(CheckupFinding finding) onFixSingle;

  @override
  State<SecurityCheckupSection> createState() => _SecurityCheckupSectionState();
}

class _SecurityCheckupSectionState extends State<SecurityCheckupSection> {
  /// 当前筛选等级：null=全部，非空=只显示该等级。
  CheckupSeverity? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = widget.report;
    final fixable = report?.fixable ?? const <CheckupFinding>[];
    final findings = report?.findings ?? const <CheckupFinding>[];
    final filtered = _filter == null
        ? findings
        : findings.where((f) => f.severity == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(l10n.securityCheckup, first: true),
        AppSectionDesc(l10n.securityCheckupDesc),
        AppSectionCard(children: [
          // 运行体检（running 时右侧转圈、禁用点击）
          AppNavRow(
            icon: Lucide.RefreshCw,
            label: widget.running ? l10n.checkupRunning : l10n.runCheckup,
            onTap: widget.running ? null : widget.onRunCheckup,
            detailBuilder: widget.running
                ? (_) => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                : null,
          ),
          // 一键修复全部（仅非 running 且存在可修复项时显示）
          if (!widget.running && fixable.isNotEmpty) ...[
            const AppSectionDivider(),
            AppNavRow(
              icon: Lucide.Wand2,
              label: l10n.checkupFix,
              detailText: '${fixable.length}',
              onTap: widget.onAutoFix,
            ),
          ],
          if (!widget.running && report != null) ...[
            if (findings.isNotEmpty) ...[
              const AppSectionDivider(),
              _buildRiskChipsRow(report),
            ],
            // 筛选后的 finding 列表
            for (final f in filtered) ...[
              const AppSectionDivider(),
              _findingRow(f, l10n),
            ],
            // 无 finding 时展示全绿状态行
            if (findings.isEmpty) ...[
              const AppSectionDivider(),
              SecurityStatusRow(
                l10n.checkupNoIssue,
                icon: Lucide.circleCheckBig,
                color: AppStatusColor.success,
              ),
            ],
          ],
        ]),
      ],
    );
  }

  /// 风险等级聚合胶囊行：高危/中危/低危数量，点击筛选。
  Widget _buildRiskChipsRow(CheckupReport report) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Wrap(
        spacing: AppGap.xs,
        runSpacing: AppGap.xs,
        children: [
          _RiskChip(
            label: '高危',
            count: report.dangerCount,
            color: AppStatusColor.danger,
            selected: _filter == CheckupSeverity.danger,
            onTap: () => setState(() => _filter =
                _filter == CheckupSeverity.danger ? null : CheckupSeverity.danger),
          ),
          _RiskChip(
            label: '中危',
            count: report.warnCount,
            color: AppStatusColor.warning,
            selected: _filter == CheckupSeverity.warn,
            onTap: () => setState(() => _filter == CheckupSeverity.warn
                ? null
                : CheckupSeverity.warn),
          ),
          _RiskChip(
            label: '低危',
            count: report.safeCount,
            color: AppStatusColor.success,
            selected: _filter == CheckupSeverity.safe,
            onTap: () => setState(() => _filter == CheckupSeverity.safe
                ? null
                : CheckupSeverity.safe),
          ),
        ],
      ),
    );
  }

  /// 单条 finding 行：severity → (图标, 语义色)，右侧可选修复按钮。
  Widget _findingRow(CheckupFinding f, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (f.severity) {
      CheckupSeverity.danger => (Lucide.CircleX, AppStatusColor.danger),
      CheckupSeverity.warn => (Lucide.circleDot, AppStatusColor.warning),
      CheckupSeverity.safe => (Lucide.circleCheckBig, AppStatusColor.success),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.sm, vertical: AppGap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧 36px 宽 severity 图标
          SizedBox(width: 36, child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: AppGap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                if (f.detail.isNotEmpty) ...[
                  const SizedBox(height: AppGap.xxxs),
                  Text(f.detail,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6))),
                ],
                if (f.fixHint != null && f.fixHint!.isNotEmpty) ...[
                  const SizedBox(height: AppGap.xxs),
                  Text('${l10n.fixHintLabel}${f.fixHint}',
                      style:
                          TextStyle(fontSize: 12, color: cs.primary)),
                ],
              ],
            ),
          ),
          // P0 修复：autoFixable 时右侧修复按钮只修当前项
          if (f.autoFixable) ...[
            const SizedBox(width: AppGap.xxs),
            Tooltip(
              message: l10n.checkupFix,
              child: IosIconButton(
                haptics: true,
                icon: Lucide.Wand2,
                size: 16,
                minSize: 32,
                onTap: () => widget.onFixSingle(f),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 风险等级聚合胶囊：彩色圆点 + 「高危 N」。
///
/// 选中态用同色实心填充 + 白字；未选中用同色 8% 底色 + 同色字。
class _RiskChip extends StatelessWidget {
  const _RiskChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : color.withValues(alpha: 0.10);
    final fg = selected ? Colors.white : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.capsule),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppGap.sm, vertical: AppGap.xxs),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.capsule),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 彩色圆点（替代 emoji 🔴🟡🟢）
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppGap.xxs),
            Text(
              '$label $count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
