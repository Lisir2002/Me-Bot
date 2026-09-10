import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../theme/design_tokens.dart';
import 'stats_card.dart';
import '../../../../l10n/build_context_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 总览
//
// 数值一律走 `formatCompactNumber`，与趋势图共用口径；
// label 交给 l10n，不再硬编码中文。
//
// 增强点：
//   · 按屏幕宽度自适应列数（2 / 3 / 4 / 6）
//   · 与上一周期对比的小字百分比（previous 为 null 时不显示）
//   · 数字切换区间时 300ms 平滑过渡
//   · launchCount 未按窗口过滤时追加「（全部）」标注
//   · 每个数字带 Semantics 语义标签
// ─────────────────────────────────────────────────────────────

/// 单个总览格子的数据描述。
class _OverviewItem {
  final String label;
  final double value;

  /// 上一周期值；为 null 时不显示对比（all 区间）。
  final double? previous;

  /// 数值格式化（用于动画插值后的文本）。
  final String Function(double v) formatter;

  /// 数值后是否追加「（全部）」标注（launchCount 未按窗口过滤时）。
  final bool annotateAll;

  const _OverviewItem({
    required this.label,
    required this.value,
    required this.previous,
    required this.formatter,
    required this.annotateAll,
  });
}

/// 总览网格：对话数 / 消息数 / 输入 / 输出 / 缓存 / 启动次数。
class StatsOverviewCard extends StatelessWidget {
  final StatsSnapshot snapshot;

  const StatsOverviewCard({super.key, required this.snapshot});

  /// 按可用宽度决定网格列数：
  ///   <400 → 2，400~800 → 3，800~1200 → 4，>1200 → 6。
  int _crossAxisCount(double width) {
    if (width < 400) return 2;
    if (width <= 800) return 3;
    if (width <= 1200) return 4;
    return 6;
  }

  /// 周期对比百分比：previous 为 null 不显示，为 0 显示「—」。
  Widget _delta(BuildContext context, double current, double? previous) {
    final cs = Theme.of(context).colorScheme;
    // 固定高度占位，保证有无对比时格子对齐
    Widget wrap(Widget child) => SizedBox(height: 12, child: child);

    if (previous == null) return wrap(const SizedBox.shrink());
    if (previous == 0) {
      return wrap(Text(
        '—',
        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
      ));
    }

    final pct = (current - previous) / previous * 100;
    final up = pct > 0;
    final down = pct < 0;
    final color = !up && !down
        ? cs.onSurfaceVariant
        : (up ? AppStatusColor.success : AppStatusColor.danger);
    final arrow = up ? '↑ ' : (down ? '↓ ' : '');
    final text = '$arrow${pct.abs().toStringAsFixed(1)}%';
    return wrap(Text(
      text,
      style: TextStyle(fontSize: 10, color: color),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final prev = snapshot.previous;

    final items = <_OverviewItem>[
      _OverviewItem(
        label: t.statsOverviewConversations,
        value: snapshot.conversationCount.toDouble(),
        previous: prev?.conversationCount.toDouble(),
        formatter: (v) => '${v.round()}',
        annotateAll: false,
      ),
      _OverviewItem(
        label: t.statsOverviewMessages,
        value: snapshot.messageCount.toDouble(),
        previous: prev?.messageCount.toDouble(),
        formatter: formatCompactNumber,
        annotateAll: false,
      ),
      _OverviewItem(
        label: t.statsOverviewPromptTokens,
        value: snapshot.promptTokens.toDouble(),
        previous: prev?.promptTokens.toDouble(),
        formatter: formatCompactNumber,
        annotateAll: false,
      ),
      _OverviewItem(
        label: t.statsOverviewCompletionTokens,
        value: snapshot.completionTokens.toDouble(),
        previous: prev?.completionTokens.toDouble(),
        formatter: formatCompactNumber,
        annotateAll: false,
      ),
      _OverviewItem(
        label: t.statsOverviewCachedTokens,
        value: snapshot.cachedTokens.toDouble(),
        previous: prev?.cachedTokens.toDouble(),
        formatter: formatCompactNumber,
        annotateAll: false,
      ),
      // 启动次数：未按窗口过滤且非 all 区间时追加「（全部）」
      _OverviewItem(
        label: t.statsOverviewLaunchCount,
        value: snapshot.launchCount.toDouble(),
        previous: prev?.launchCount.toDouble(),
        formatter: (v) => '${v.round()}',
        annotateAll:
            !snapshot.launchCountFiltered && snapshot.range != StatsRange.all,
      ),
    ];

    return StatsSectionCard(
      title: t.statsSectionOverview,
      // 用 LayoutBuilder 拿到卡片可用宽度，决定列数
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _crossAxisCount(constraints.maxWidth);
          return GridView.count(
            crossAxisCount: count,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            children: [
              for (final item in items) _cell(context, cs, item),
            ],
          );
        },
      ),
    );
  }

  /// 单个总览格子：主数值（动画）+ 周期对比 + label。
  Widget _cell(BuildContext context, ColorScheme cs, _OverviewItem item) {
    final valueText = item.formatter(item.value);
    return Semantics(
      label: '${item.label}: $valueText',
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 主数值 + 可选「（全部）」小标注
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AnimatedNumber(
                    value: item.value,
                    formatter: item.formatter,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  if (item.annotateAll)
                    Text(
                      '(all)',
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              // 周期对比（固定高度，无对比时占位）
              _delta(context, item.value, item.previous),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
