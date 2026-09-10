// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';

import '../../../core/services/security/credential_audit_logger.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_section_header.dart';
import '../../../theme/design_tokens.dart';
import 'security_shared.dart';

/// 最近安全事件 section（安全中心第⑤段）。
///
/// 从 security_page.dart 拆出，职责：
/// - 审计日志时间线视图（新功能 6：左轴 + 圆点 + Check/X 图标）
/// - 按 action 类型横向筛选 Chip 行
/// - 分页加载（P2 修复：不再硬编码 12 条，由 [currentLimit] 控制）
/// - 底部清除审计按钮（生物验证 + 确认由父级 [onClear] 实现）
class SecurityAuditSection extends StatefulWidget {
  const SecurityAuditSection({
    super.key,
    required this.audit,
    required this.loading,
    required this.onLoadMore,
    required this.onClear,
    required this.currentLimit,
    required this.hasMore,
  });

  /// 当前已加载的审计事件列表（新→旧）。
  final List<AuditEvent> audit;

  /// 首次加载中。
  final bool loading;

  /// 加载更多，参数为新的 limit（父级重新拉取后回传新列表）。
  final Future<void> Function(int limit) onLoadMore;

  /// 清除审计（已包含生物验证 + 确认，由父级实现）。
  final Future<void> Function() onClear;

  /// 当前显示条数限制。
  final int currentLimit;

  /// 是否还有更多事件可加载。
  final bool hasMore;

  @override
  State<SecurityAuditSection> createState() => _SecurityAuditSectionState();
}

class _SecurityAuditSectionState extends State<SecurityAuditSection> {
  /// 当前筛选的 action；null = 全部。
  /// [_otherKey] 表示「其他」（未在已知映射中的 action）。
  String? _filterAction;

  static const String _otherKey = '__other__';

  /// 已知 action 集合（用于区分「其他」分组）。
  static const Set<String> _knownActions = {
    'view',
    'copy',
    'export',
    'enterPassphrase',
    'migrate',
    'clearAudit',
    'fix',
    'markRotated',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(l10n.auditTrail),
        AppSectionDesc(l10n.auditTrailDesc),
        AppSectionCard(children: _buildChildren(l10n)),
      ],
    );
  }

  List<Widget> _buildChildren(AppLocalizations l10n) {
    if (widget.loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppGap.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (widget.audit.isEmpty) {
      return [
        SecurityStatusRow(
          l10n.auditEmpty,
          icon: Lucide.ScrollText,
        ),
      ];
    }

    final filtered = widget.audit.where(_matchesFilter).toList();

    return [
      // ── 筛选 Chip 行 ──
      _buildFilterChips(l10n),
      // ── 时间线列表 ──
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppGap.lg),
          child: Center(
            child: Text(
              '当前分类下暂无记录',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
        )
      else
        for (var i = 0; i < filtered.length; i++)
          _timelineItem(l10n, filtered[i], i == filtered.length - 1),
      // ── 加载更多 ──
      if (widget.hasMore) ...[
        const AppSectionDivider(),
        AppNavRow(
          icon: Lucide.ChevronDown,
          label: '加载更多',
          onTap: () => widget.onLoadMore(widget.currentLimit + 20),
        ),
      ],
      // ── 清除审计 ──
      const AppSectionDivider(),
      AppNavRow(
        icon: Lucide.Eraser,
        label: l10n.auditClear,
        onTap: widget.onClear,
      ),
    ];
  }

  // ── 筛选逻辑 ──

  bool _matchesFilter(AuditEvent e) {
    final f = _filterAction;
    if (f == null) return true;
    if (f == _otherKey) return !_knownActions.contains(e.action);
    return e.action == f;
  }

  /// action → 短标签（筛选 Chip 用，内联中文）。
  String _chipLabel(String action) {
    switch (action) {
      case 'view':
        return '查看';
      case 'copy':
        return '复制';
      case 'export':
        return '导出';
      case 'enterPassphrase':
        return '输入口令';
      case 'migrate':
        return '迁移';
      case 'clearAudit':
        return '清空';
      case 'fix':
        return '修复';
      case 'markRotated':
        return '标记轮换';
      default:
        return action;
    }
  }

  Widget _buildFilterChips(AppLocalizations l10n) {
    // 收集当前列表中实际出现的 action。
    final present = <String>{};
    for (final e in widget.audit) {
      present.add(e.action);
    }
    final knownPresent =
        present.where(_knownActions.contains).toList()..sort();
    final hasUnknown = present.any((a) => !_knownActions.contains(a));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppGap.sm, AppGap.xs, AppGap.sm, AppGap.xxs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('全部', _filterAction == null, () {
              setState(() => _filterAction = null);
            }),
            for (final a in knownPresent) ...[
              const SizedBox(width: AppGap.xs),
              _chip(_chipLabel(a), _filterAction == a, () {
                setState(() => _filterAction = a);
              }),
            ],
            if (hasUnknown) ...[
              const SizedBox(width: AppGap.xs),
              _chip('其他', _filterAction == _otherKey, () {
                setState(() => _filterAction = _otherKey);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppGap.sm, vertical: AppGap.xxs),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.capsule),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  // ── 时间线 ──

  /// 单条时间线项：左轴（圆点 + 竖线）+ 右侧事件内容。
  Widget _timelineItem(
    AppLocalizations l10n,
    AuditEvent e,
    bool isLast,
  ) {
    final cs = Theme.of(context).colorScheme;
    final dotColor = e.ok ? AppStatusColor.success : AppStatusColor.danger;
    final actionText = _actionLabel(e.action, l10n);
    final failSuffix = e.ok ? '' : ' · ${l10n.auditFailed}';

    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppGap.sm, vertical: AppGap.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间轴列
            Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                  child: Icon(
                    e.ok ? Lucide.Check : Lucide.X,
                    size: 9,
                    color: Colors.white,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppGap.sm),
            // 事件内容列
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '$actionText · ${e.target}$failSuffix',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppGap.sm),
                      Text(
                        fmtTime(e.time),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// action → 本地化展示名（与原 security_page 一致）。
  String _actionLabel(String action, AppLocalizations l10n) {
    return switch (action) {
      'view' => l10n.auditActionView,
      'copy' => l10n.auditActionCopy,
      'export' => l10n.auditActionExport,
      'enterPassphrase' => l10n.auditActionEnterPassphrase,
      'migrate' => l10n.auditActionMigrate,
      'clearAudit' => l10n.auditActionClearAudit,
      'fix' => l10n.auditActionFix,
      'markRotated' => l10n.auditActionMarkRotated,
      _ => action,
    };
  }
}
