import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../theme/design_tokens.dart';
import 'stats_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/build_context_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 用量趋势（堆叠柱）
//
// 旧实现有三个硬伤：
//   1. Y 轴用「所有模型加总 ×1.2」当 maxY，但每根柱子的高度只是**单个模型**
//      的值 —— 于是柱子永远够不到顶，图上常年留一大块空白。
//      → 改成一根柱子 = 该时间桶的总量，内部按模型堆叠成段。
//   2. 桶粒度用 `messages.first.timestamp` 判断，而 messages 是按会话拼出来的，
//      顺序没有保证 → 跨度判错、天/月乱切。
//      → 粒度在 `StatsSnapshot` 里用真实 min~max 跨度算好。
//   3. 颜色按「首次出现顺序」分配，换个区间图例配色就跳变。
//      → 模型名排序后取模取色，同一模型永远同一颜色。
//
// 另外补上：图例可点击（点一下隐藏/恢复该模型）、桶多时横向滚动、
// tooltip 给出该桶的总量与各模型分项。
// ─────────────────────────────────────────────────────────────

/// 用量趋势区块。
class StatsTrendCard extends StatefulWidget {
  final StatsSnapshot snapshot;

  const StatsTrendCard({super.key, required this.snapshot});

  @override
  State<StatsTrendCard> createState() => _StatsTrendCardState();
}

class _StatsTrendCardState extends State<StatsTrendCard> {
  /// 被图例隐藏的模型（只影响展示，不改数据）。
  final Set<String> _hidden = <String>{};

  @override
  void didUpdateWidget(covariant StatsTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      // 换区间后模型列表可能变了，清掉已不存在的隐藏项，
      // 否则新模型可能被「隐形」地过滤掉而图例里看不到。
      final alive = widget.snapshot.trend.models.toSet();
      _hidden.removeWhere((m) => !alive.contains(m));
    }
  }

  static const List<Color> _palette = [
    Color(0xFF4C6FFF), // 蓝
    Color(0xFF10B981), // 绿
    Color(0xFFF59E0B), // 橙
    Color(0xFFEF4444), // 红
    Color(0xFF8B5CF6), // 紫
    Color(0xFF06B6D4), // 青
    Color(0xFFEC4899), // 粉
    Color(0xFF84CC16), // 黄绿
  ];

  TrendSeries get _trend => widget.snapshot.trend;

  Color _colorFor(String model) {
    final i = _trend.models.indexOf(model);
    return _palette[(i < 0 ? 0 : i) % _palette.length];
  }

  List<String> get _visible =>
      _trend.models.where((m) => !_hidden.contains(m)).toList();

  double get _barWidth {
    final n = _trend.buckets.length;
    if (_trend.daily) {
      if (n <= 14) return 18;
      if (n <= 31) return 12;
      return 7;
    }
    if (n <= 12) return 28;
    if (n <= 24) return 18;
    return 12;
  }

  String _bucketLabel(DateTime d, int index) {
    if (_trend.daily) return '${d.month}/${d.day}';
    // 每月 1 月或首桶补上年份，避免跨年后只剩月份造成歧义
    if (d.month == 1 || index == 0) {
      return '${d.year.toString().substring(2)}/${d.month}';
    }
    return '${d.month}';
  }

  String _modelLabel(String m) {
    if (m == StatsSnapshot.unknownModelKey) {
      return context.l10n.statsUnknownModel;
    }
    if (m.length <= 20) return m;
    return '${m.substring(0, 19)}…';
  }

  /// 把 max 抬到一个「整齐」的上界（1/2/2.5/5/10 × 10^n）。
  static double _niceMax(double v) {
    if (v <= 0) return 1;
    final exp = (math.log(v) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final n = v / base;
    final step = n <= 1
        ? 1.0
        : n <= 2
            ? 2.0
            : n <= 2.5
                ? 2.5
                : n <= 5
                    ? 5.0
                    : 10.0;
    return step * base;
  }

  /// 左轴刻度间隔：1/2/5 × 10^n，保证刻度落在整数上。
  static double _niceInterval(double maxY) {
    final raw = maxY / 4;
    if (raw <= 1) return 1;
    final exp = (math.log(raw) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final n = raw / base;
    final step = n <= 1 ? 1.0 : n <= 2 ? 2.0 : n <= 5 ? 5.0 : 10.0;
    final v = step * base;
    return v < 1 ? 1 : v;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final trend = _trend;

    final visible = _visible;
    final empty = trend.isEmpty || trend.maxTotal <= 0 ||
        (visible.isEmpty && trend.models.isNotEmpty);

    return StatsSectionCard(
      title: t.statsSectionTrend,
      trailing: trend.isEmpty
          ? null
          : _GranularityChip(
              text: trend.daily ? t.statsGranularityDay : t.statsGranularityMonth,
            ),
      child: empty
          ? StatsEmptyHint(text: t.statsNoData)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final slot = _barWidth + 12;
                    // 极端情况下（例如被放进无限宽容器）保底，避免 maxWidth=infinity
                    final available = constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : 320.0;
                    final chartW =
                        math.max(available, trend.buckets.length * slot);

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: chartW,
                        height: 200,
                        child: _buildChart(context, visible),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppGap.sm),
                _buildLegend(context, t),
              ],
            ),
    );
  }

  Widget _buildChart(BuildContext context, List<String> visible) {
    final t = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final trend = _trend;

    final groups = <BarChartGroupData>[];
    var peak = 0;
    for (int i = 0; i < trend.buckets.length; i++) {
      final b = trend.buckets[i];
      var acc = 0.0;
      final items = <BarChartRodStackItem>[];
      for (final m in visible) {
        final v = (b.byModel[m] ?? 0).toDouble();
        if (v <= 0) continue;
        items.add(BarChartRodStackItem(acc, acc + v, _colorFor(m)));
        acc += v;
      }
      if (acc > peak) peak = acc.toInt();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: acc,
              width: _barWidth,
              color: Colors.transparent, // 只显示堆叠段
              borderRadius: BorderRadius.zero,
              rodStackItems: items,
            ),
          ],
        ),
      );
    }

    final maxY = _niceMax(peak.toDouble());
    final interval = _niceInterval(maxY);
    final labelStep =
        math.max(1, (trend.buckets.length / 7).ceil()).clamp(1, 1000).toInt();

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            tooltipRoundedRadius: 10,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            maxContentWidth: 240,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipBorder: BorderSide(
              color: cs.onInverseSurface.withValues(alpha: 0.12),
            ),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final i = group.x;
              if (i < 0 || i >= trend.buckets.length) return null;
              final b = trend.buckets[i];
              final total = b.totalFor(visible);
              return BarTooltipItem(
                '${_bucketLabel(b.date, i)}\n'
                '${t.statsTrendTotal('${formatCompactNumber(total)} ${t.statsTokensUnit}')}',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  for (final m in visible)
                    TextSpan(
                      text: '\n● ${_modelLabel(m)}  '
                          '${formatCompactNumber(b.byModel[m] ?? 0)}',
                      style: TextStyle(
                        color: _colorFor(m),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value != 0 && value % interval != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    formatAxisNumber(value),
                    style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 ||
                    idx >= trend.buckets.length ||
                    value != idx.toDouble()) {
                  return const SizedBox.shrink();
                }
                final isLast = idx == trend.buckets.length - 1;
                if (!isLast && idx % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    _bucketLabel(trend.buckets[idx].date, idx),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.onSurfaceVariant.withValues(alpha: 0.15),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: cs.onSurfaceVariant.withValues(alpha: 0.25),
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }

  Widget _buildLegend(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final m in _trend.models)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (_hidden.contains(m)) {
                _hidden.remove(m);
              } else if (_hidden.length < _trend.models.length - 1) {
                // 至少留一个模型，否则图会全空
                _hidden.add(m);
              }
            }),
            child: Opacity(
              opacity: _hidden.contains(m) ? 0.38 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colorFor(m),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _modelLabel(m),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 标题右侧的粒度提示（按天 / 按月）。
class _GranularityChip extends StatelessWidget {
  final String text;

  const _GranularityChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }
}
