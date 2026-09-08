import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────
// 统计页通用 UI 原子
//
// 卡片 / 空态 / 表头 / 胶囊行，四个 Section 共用。
// 抽出来是为了让 heatmap / trend / overview / tables 四个文件
// 只关心自己的数据与交互。
// ─────────────────────────────────────────────────────────────

/// 统一的区块卡片：标题 + 可选右侧挂件 + 内容。
class StatsSectionCard extends StatelessWidget {
  final String title;

  /// 标题右侧的小挂件（如「按天/按月」粒度提示）。
  final Widget? trailing;
  final Widget child;

  const StatsSectionCard({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppGap.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppGap.md),
          child,
        ],
      ),
    );
  }
}

/// 区块空态。
class StatsEmptyHint extends StatelessWidget {
  final String text;

  const StatsEmptyHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppGap.xl),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 表头：左列名 + 右列名（小字灰色，两端对齐）。
class StatsTableHeader extends StatelessWidget {
  final String left;
  final String right;

  const StatsTableHeader({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
      ),
    );
  }
}

/// 胶囊数据行：徽章 + 名称 + 数值。
class StatsPillRow extends StatelessWidget {
  final String? badge;
  final IconData? badgeIcon;
  final String name;
  final String value;

  const StatsPillRow({
    super.key,
    this.badge,
    this.badgeIcon,
    required this.name,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Widget badgeWidget;
    if (badgeIcon != null) {
      badgeWidget = Icon(badgeIcon, size: 16, color: cs.primary);
    } else {
      badgeWidget = Text(
        badge ?? '?',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: badgeWidget,
          ),
          const SizedBox(width: AppGap.sm),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 位数压缩：1234 → 1.2K，1_200_000 → 1.2M。
///
/// 图表坐标轴、卡片数值共用同一套口径，避免同一数字在不同模块
/// 显示成两种样子。
String formatCompactNumber(num v) {
  final d = v.toDouble();
  if (d.abs() >= 1000000) return '${(d / 1000000).toStringAsFixed(1)}M';
  if (d.abs() >= 10000) return '${(d / 1000).toStringAsFixed(0)}K';
  if (d.abs() >= 1000) return '${(d / 1000).toStringAsFixed(1)}K';
  return d.round().toString();
}

/// 坐标轴刻度专用：数值更「整」，避免出现 1.2K 这种半格刻度。
String formatAxisNumber(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.round().toString();
}
