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
///
/// [subValue] 非空时在主数值下方追加一行小字灰色副数值
/// （如「12.3K tokens」），主副两行右对齐。
class StatsPillRow extends StatelessWidget {
  final String? badge;
  final IconData? badgeIcon;
  final String name;
  final String value;

  /// 副数值（小字灰色），可为 null。
  final String? subValue;

  const StatsPillRow({
    super.key,
    this.badge,
    this.badgeIcon,
    required this.name,
    required this.value,
    this.subValue,
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
          // 主数值；有副数值时主副两行右对齐（副数值小字灰色）
          if (subValue == null)
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  subValue!,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
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

// ─────────────────────────────────────────────────────────────
// 动画与骨架屏
// ─────────────────────────────────────────────────────────────

/// 数字平滑过渡：[value] 变化时用 300ms easeOut 补间动画滚动到新值。
///
/// 区间切换时，`TweenAnimationBuilder` 会从上一帧显示的中间值继续
/// 动画，而不是从 0 跳变，因此切换区间不会出现数字回跳。
class AnimatedNumber extends StatelessWidget {
  /// 当前目标值。
  final double value;

  /// 把插值后的 double 格式化成展示文本（如整数或压缩单位）。
  final String Function(double v) formatter;

  /// 文本样式（字号 / 字重 / 颜色）。
  final TextStyle? style;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, v, _) => Text(formatter(v), style: style),
    );
  }
}

/// 统计页骨架屏：数据加载完成前的灰色占位，带从左到右扫过的 shimmer 高光。
///
/// 结构与真实页面一致：总览 6 格（3 列 2 行圆角矩形）、热力图小方块行、
/// 趋势图高低错落的柱子、三张表的胶囊行。
class StatsSkeleton extends StatefulWidget {
  const StatsSkeleton({super.key});

  @override
  State<StatsSkeleton> createState() => _StatsSkeletonState();
}

class _StatsSkeletonState extends State<StatsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 单个灰色占位块：ShaderMask 叠加一条随动画平移的浅色高光带。
  Widget _block({double? width, double height = 16, double radius = 8}) {
    final cs = Theme.of(context).colorScheme;
    // 基色 / 高光色都由 onSurface 透明度派生，自动适配明暗主题
    final base = cs.onSurface.withValues(alpha: 0.06);
    final hi = cs.onSurface.withValues(alpha: 0.12);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 高光带从左(-)滑到右(+)
        final t = _controller.value;
        final center = -1.4 + 2.8 * t;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(center - 0.4, 0),
            end: Alignment(center + 0.4, 0),
            colors: [base, hi, base],
            stops: const [0.4, 0.5, 0.6],
          ).createShader(rect),
          child: child,
        );
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 600,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区块标题占位
          _block(width: 120, height: 18, radius: 6),
          const SizedBox(height: AppGap.md),
          // 总览 6 格：3 列 2 行
          for (var r = 0; r < 2; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppGap.sm),
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _block(height: 56, radius: AppRadius.md),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppGap.md),
          // 热力图占位：一行小方块
          Wrap(
            spacing: AppGap.xxs,
            runSpacing: AppGap.xxs,
            children: [
              for (var i = 0; i < 14; i++)
                _block(width: 14, height: 14, radius: AppRadius.tiny),
            ],
          ),
          const SizedBox(height: AppGap.lg),
          // 趋势图占位：几根不同高度的柱子
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in const [40.0, 80.0, 55.0, 100.0, 65.0, 90.0, 45.0, 75.0])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppGap.xxs),
                      child: _block(height: h, radius: AppRadius.tiny),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppGap.lg),
          // 三张表占位：每行一个灰色胶囊
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppGap.xs),
              child: _block(height: 52, radius: AppRadius.lg),
            ),
        ],
      ),
    );
  }
}
