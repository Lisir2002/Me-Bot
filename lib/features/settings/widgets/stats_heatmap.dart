import 'dart:ui' as ui show TextDirection;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../theme/design_tokens.dart';
import 'stats_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/build_context_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 聊天热力图 · 深度重构版
//
// 对标全网四套主流实现（GitHub 贡献图 / cal-heatmap / ECharts
// calendar / react-calendar-heatmap）后的定稿：
//
//  1. 分级算法：GitHub 官方是「去离群值后按四分位数」分级，而不是
//     count/max 线性映射。四分位数对离群值天然稳健——某天爆量 500 条
//     不会把其余所有天压成同一档浅色。本实现取显示窗口内的非零计数
//     排序，以 Q1/Q2/Q3 为切点分 5 档（0 / ≤Q1 / ≤Q2 / ≤Q3 / >Q3），
//     且每次切换时间范围都按当前窗口重算（GitHub 同为「相对当前
//     视图」而非全局）。
//  2. 离散 5 档 > 连续渐变：人眼稳定区分的状态数约 5 个，
//     cal-heatmap 的 scaleQuantize 与 ECharts 的 piecewise visualMap
//     均为分档方案。
//  3. 交互：桌面端 MouseRegion 悬停即时出跟随浮层（GitHub 式），
//     移动端点按选中；空态用独立文案「{date} 无聊天记录」
//     （GitHub: "No contributions on March 3rd"），日期走
//     MaterialLocalizations 本地化格式。
//  4. 头部汇总：窗口内总消息数带千分位（GitHub: "1,876 contributions
//     in the last year"），数字加粗。
//  5. 月份标签对齐「包含当月 1 号的那一周列」，放不下就跳过
//     （GitHub 不做 clamp，clamp 会造成标签重叠）。
//  6. 周首日跟随 MaterialLocalizations.firstDayOfWeek（GitHub 固定
//     周日，这里本地化更优），每列固定 7 天，首尾不齐的补位格不绘制，
//     使网格视觉边界与数据边界一致。
//  7. 入场动画：从左到右逐列波浪淡入（GitHub / cal-heatmap 均有
//     animationDuration）。
//  8. 网格外缘格子放大圆角；悬停格描边高亮（ECharts emphasis）。
// ─────────────────────────────────────────────────────────────

/// 热力图区块。
class StatsHeatmapCard extends StatefulWidget {
  final StatsSnapshot snapshot;

  const StatsHeatmapCard({super.key, required this.snapshot});

  @override
  State<StatsHeatmapCard> createState() => _StatsHeatmapCardState();
}

/// 浮层锚定的活跃日（格子坐标随命中测试一并记下，免得渲染时反查）。
class _ActiveDay {
  final DateTime day;
  final int col;
  final int row;

  const _ActiveDay(this.day, this.col, this.row);
}

class _StatsHeatmapCardState extends State<StatsHeatmapCard>
    with SingleTickerProviderStateMixin {
  /// 移动端点按选中的日期。
  _ActiveDay? _selected;

  /// 桌面端悬停的日期（优先于选中态展示浮层）。
  _ActiveDay? _hovered;

  final ScrollController _hScroll = ScrollController();

  /// 是否在下一帧把网格滚到最右端（当月）。
  bool _pendingScrollToEnd = true;

  /// 入场动画：0..1，列级波浪淡入。
  late final AnimationController _entry;

  static final NumberFormat _thousand = NumberFormat.decimalPattern();

  // 网格几何：色块 14 + 间距 3 = 17
  static const double _colW = 17;
  static const double _rowH = 17;
  static const double _labelW = 22;
  static const double _labelH = 18;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void didUpdateWidget(covariant StatsHeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      // 换区间后旧选中/悬停日可能已经不在窗口内，直接清掉
      _selected = null;
      _hovered = null;
      _pendingScrollToEnd = true;
      _entry.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_pendingScrollToEnd || !mounted || !_hScroll.hasClients) return;
    _pendingScrollToEnd = false;
    _hScroll.jumpTo(_hScroll.position.maxScrollExtent);
  }

  /// 热力图展示窗口。
  StatsWindow _window(DateTime now) {
    final w = widget.snapshot.window;
    if (widget.snapshot.range != StatsRange.all) return w;

    final today = DateTime(now.year, now.month, now.day);
    final fourMonthsAgo = DateTime(now.year, now.month - 4, 1);
    final earliest = widget.snapshot.earliestDay;
    var start = (earliest != null && earliest.isBefore(fourMonthsAgo))
        ? earliest
        : fourMonthsAgo;
    final minStart = today.subtract(const Duration(days: 53 * 7 - 1));
    if (start.isBefore(minStart)) start = minStart;
    return StatsWindow(start: start, end: today);
  }

  /// 以窗口起点所在「本地周首日」为首列，生成覆盖整个窗口的周列。
  ///
  /// [firstDayIndex] 为 `MaterialLocalizations.firstDayOfWeekIndex`
  /// 语义：0=周日..6=周六。每列固定 7 天；首尾列超出窗口的补位格
  /// 由绘制层跳过。
  List<List<DateTime>> _buildWeeks(StatsWindow window, int firstDayIndex) {
    // DateTime.weekday: Mon=1..Sun=7；Dart 的 % 恒非负，无需再包一层
    final firstWeekday = firstDayIndex == 0 ? 7 : firstDayIndex;
    final shift = (window.start!.weekday - firstWeekday) % 7;
    var cursor = window.start!.subtract(Duration(days: shift));
    final weeks = <List<DateTime>>[];
    while (!cursor.isAfter(window.end!)) {
      weeks.add(List.generate(7, (i) => cursor.add(Duration(days: i))));
      cursor = cursor.add(const Duration(days: 7));
    }
    return weeks;
  }

  /// 四分位分级标尺（GitHub 算法，见文件头注释）。
  _HeatmapScale _buildScale(List<List<DateTime>> weeks, StatsWindow window) {
    final dayCounts = widget.snapshot.messagesByDay;
    final counts = <int>[];
    for (final col in weeks) {
      for (final day in col) {
        if (!window.contains(day)) continue;
        final v = dayCounts[day] ?? 0;
        if (v > 0) counts.add(v);
      }
    }
    return _HeatmapScale.compute(counts);
  }

  /// 命中测试：返回格子坐标；范围外返回 null（不响应）。
  _ActiveDay? _dayAt(Offset pos, List<List<DateTime>> weeks, StatsWindow w) {
    final col = (pos.dx / _colW).floor();
    final row = (pos.dy / _rowH).floor();
    if (col < 0 || col >= weeks.length || row < 0 || row >= 7) return null;
    final day = weeks[col][row];
    if (!w.contains(day)) return null;
    return _ActiveDay(day, col, row);
  }

  void _handleHover(Offset pos, List<List<DateTime>> weeks, StatsWindow w) {
    final hit = _dayAt(pos, weeks, w);
    if (hit == null) {
      if (_hovered != null) setState(() => _hovered = null);
      return;
    }
    // 同一天内移动不重建（避免浮层闪烁）
    if (_hovered?.day != hit.day) setState(() => _hovered = hit);
  }

  void _handleTap(Offset pos, List<List<DateTime>> weeks, StatsWindow w) {
    final hit = _dayAt(pos, weeks, w);
    if (hit == null) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    // 再次点击同一天 → 取消
    setState(() =>
        _selected = _selected?.day == hit.day ? null : hit);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ml = MaterialLocalizations.of(context);
    final dayCounts = widget.snapshot.messagesByDay;
    final now = DateTime.now();

    final window = _window(now);
    final weeks = _buildWeeks(window, ml.firstDayOfWeekIndex);
    final scale = _buildScale(weeks, window);

    // 头部汇总：窗口内总消息数（千分位 + 数字加粗）
    var total = 0;
    for (final d in dayCounts.entries) {
      if (window.contains(d.key)) total += d.value;
    }
    final countStr = _thousand.format(total);
    final template = t.statsHeatmapSummary('@');
    final parts = template.split('@');

    // 5 档调色板：0 无消息 / 1~4 递增（跟随主题 primary，深浅色自适应）
    final palette = <Color>[
      cs.surfaceContainerHighest.withValues(alpha: 0.8),
      cs.primary.withValues(alpha: 0.25),
      cs.primary.withValues(alpha: 0.45),
      cs.primary.withValues(alpha: 0.70),
      cs.primary,
    ];

    final narrow = ml.narrowWeekdays;
    final firstDay = ml.firstDayOfWeekIndex;
    final gridH = 7 * _rowH;
    final gridW = weeks.length * _colW;

    // 浮层当前锚点：悬停优先，点按其次（桌面悬停时点按也能看到）
    final active = _hovered ?? _selected;

    return StatsSectionCard(
      title: t.statsSectionHeatmap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部汇总
          if (parts.length == 2)
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
                children: [
                  TextSpan(text: parts[0]),
                  TextSpan(
                    text: countStr,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  TextSpan(text: parts[1]),
                ],
              ),
            )
          else
            Text(t.statsHeatmapSummary(countStr),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          // x 轴：月份标签固定在顶部，随网格滚动偏移实时重绘（粘性刻度）
          Row(
            children: [
              const SizedBox(width: _labelW),
              Expanded(
                child: SizedBox(
                  height: _labelH,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _hScroll,
                      builder: (context, _) {
                        final offset = _hScroll.hasClients
                            ? _hScroll.position.pixels
                            : 0.0;
                        return CustomPaint(
                          size: Size.infinite,
                          painter: _MonthLabelsPainter(
                            weeks: weeks,
                            offset: offset,
                            color: cs.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
              height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
          const SizedBox(height: AppGap.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // y 轴：周几标签（第 1/3/5 行；narrowWeekdays 固定周日起始，
              // 按 firstDayOfWeekIndex 偏移映射到本地周序）
              Column(
                children: [
                  for (int i = 0; i < 7; i++)
                    SizedBox(
                      height: _rowH,
                      width: _labelW,
                      child: Center(
                        child: Text(
                          (i == 0 || i == 2 || i == 4)
                              ? narrow[(firstDay + i) % 7]
                              : '',
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hScroll,
                  child: MouseRegion(
                    onHover: (e) => _handleHover(
                        e.localPosition, weeks, window),
                    onExit: (_) {
                      if (_hovered != null) {
                        setState(() => _hovered = null);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) =>
                          _handleTap(d.localPosition, weeks, window),
                      child: SizedBox(
                        width: gridW,
                        height: gridH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _HeatmapGridPainter(
                                  weeks: weeks,
                                  dayCounts: dayCounts,
                                  scale: scale,
                                  window: window,
                                  selected: _selected,
                                  hovered: _hovered,
                                  palette: palette,
                                  ringColor: cs.onSurface,
                                  entry: _entry,
                                ),
                              ),
                            ),
                            if (active != null)
                              _DayDetailOverlay(
                                col: active.col,
                                row: active.row,
                                text: _detailText(active.day, t),
                                gridWidth: gridW,
                                gridHeight: gridH,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 图例：0~4 级全列出，右对齐（不随网格滚动）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(t.statsLegendLess,
                  style:
                      TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              for (int lv = 0; lv <= 4; lv++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: palette[lv],
                    borderRadius: BorderRadius.circular(2),
                    border: lv == 0
                        ? Border.all(
                            color:
                                cs.outlineVariant.withValues(alpha: 0.6))
                        : null,
                  ),
                ),
              const SizedBox(width: 4),
              Text(t.statsLegendMore,
                  style:
                      TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  String _detailText(DateTime day, AppLocalizations t) {
    final count = widget.snapshot.messagesByDay[day] ?? 0;
    final dateStr =
        MaterialLocalizations.of(context).formatMediumDate(day);
    return count > 0
        ? t.statsHeatmapDayDetail(dateStr, count)
        : t.statsHeatmapNoActivity(dateStr);
  }
}

/// 四分位分级标尺。
///
/// 取窗口内非零计数排序后按 Q1/Q2/Q3 切 4 段（0 单独一档）。
/// 四分位数对离群值稳健——等价于 GitHub「去离群值后四分位」的
/// 实际效果，且不需要显式定义离群值判定规则。
class _HeatmapScale {
  final int q1, q2, q3;

  const _HeatmapScale(this.q1, this.q2, this.q3);

  factory _HeatmapScale.compute(List<int> nonzeroCounts) {
    if (nonzeroCounts.isEmpty) return const _HeatmapScale(1, 1, 1);
    final s = List<int>.from(nonzeroCounts)..sort();
    int q(int rank) => s[((s.length - 1) * rank) ~/ 4];
    final a = q(1), b = q(2), c = q(3);
    // 退化保护：保证切点严格递增，避免低档全被吞掉
    var q1 = a, q2 = b, q3 = c;
    if (q2 <= q1) q2 = q1 + 1;
    if (q3 <= q2) q3 = q2 + 1;
    return _HeatmapScale(q1, q2, q3);
  }

  int level(int count) {
    if (count <= 0) return 0;
    if (count <= q1) return 1;
    if (count <= q2) return 2;
    if (count <= q3) return 3;
    return 4;
  }
}

/// 选中/悬停格子的详情浮层。
///
/// 刻意做成 Widget 而不是画在 Canvas 里：主题色、字号、阴影都跟随
/// Theme，且不会被 CustomPaint 的画布边界裁切。
class _DayDetailOverlay extends StatelessWidget {
  final int col;
  final int row;
  final String text;
  final double gridWidth;
  final double gridHeight;

  const _DayDetailOverlay({
    required this.col,
    required this.row,
    required this.text,
    required this.gridWidth,
    required this.gridHeight,
  });

  static const double _cell = 14;
  static const double _colW = 17;
  static const double _rowH = 17;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      color: cs.onInverseSurface,
      fontWeight: FontWeight.w600,
    );

    // 先量一次文字宽度，才能把浮层摆正（避免写死宽度导致偏移）
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    const padH = 8.0;
    const padV = 6.0;
    const bubbleH = 26.0;
    final bubbleW = tp.width + padH * 2;

    var x = col * _colW + _cell / 2 - bubbleW / 2;
    x = x.clamp(0.0, (gridWidth - bubbleW).clamp(0.0, gridWidth)).toDouble();
    // 上方三行气泡朝下，下方四行气泡朝上，保证不越界
    final y = row <= 2 ? row * _rowH + _cell + 5 : row * _rowH - 5 - bubbleH;
    final clampedY =
        y.clamp(0.0, (gridHeight - bubbleH).clamp(0.0, gridHeight)).toDouble();

    return Positioned(
      left: x,
      top: clampedY,
      child: IgnorePointer(
        child: Container(
          height: bubbleH,
          padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: cs.inverseSurface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(text, style: style, maxLines: 1),
          ),
        ),
      ),
    );
  }
}

/// 热力图网格：色块 + 悬停/选中描边 + 列级波浪入场动画。
class _HeatmapGridPainter extends CustomPainter {
  final List<List<DateTime>> weeks;
  final Map<DateTime, int> dayCounts;
  final _HeatmapScale scale;
  final StatsWindow window;
  final _ActiveDay? selected;
  final _ActiveDay? hovered;
  final List<Color> palette;
  final Color ringColor;
  final Animation<double> entry;

  _HeatmapGridPainter({
    required this.weeks,
    required this.dayCounts,
    required this.scale,
    required this.window,
    required this.selected,
    required this.hovered,
    required this.palette,
    required this.ringColor,
    required this.entry,
  }) : super(repaint: entry);

  static const double _cell = 14;
  static const double _colW = 17;
  static const double _rowH = 17;

  /// 列 i 的入场进度：从左到右依次出现，各列占 0.6 归一化时间，
  /// 自身淡入占 0.4。
  double _columnProgress(int col, double t) {
    final n = weeks.length;
    if (n <= 1) return t;
    final start = (col / n) * 0.6;
    return ((t - start) / 0.4).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellPaint = Paint();
    final t = Curves.easeOut.transform(entry.value);
    final lastCol = weeks.length - 1;

    for (int c = 0; c < weeks.length; c++) {
      final colT = _columnProgress(c, t);
      if (colT <= 0) continue;
      for (int r = 0; r < 7; r++) {
        final day = weeks[c][r];
        // 周对齐补位产生的窗口外格子不绘制，使网格边界贴合数据
        if (!window.contains(day)) continue;
        final base = palette[scale.level(dayCounts[day] ?? 0)];
        cellPaint.color = base.withValues(alpha: base.a * colT);
        canvas.drawRRect(_cellRect(c, r, lastCol), cellPaint);
      }
    }

    // 悬停高亮（半透明）+ 选中描边（实线）
    _drawRing(canvas, hovered, 1.5, ringColor.withValues(alpha: 0.45));
    _drawRing(canvas, selected, 2, ringColor);
  }

  RRect _cellRect(int c, int r, int lastCol) {
    final rect = Rect.fromLTWH(c * _colW, r * _rowH, _cell, _cell);
    // 网格外缘用大圆角，内部统一小圆角
    const inner = Radius.circular(3);
    const outer = Radius.circular(6);
    return RRect.fromRectAndCorners(
      rect,
      topLeft: c == 0 && r == 0 ? outer : inner,
      topRight: c == lastCol && r == 0 ? outer : inner,
      bottomLeft: c == 0 && r == 6 ? outer : inner,
      bottomRight: c == lastCol && r == 6 ? outer : inner,
    );
  }

  void _drawRing(Canvas canvas, _ActiveDay? cell, double width, Color color) {
    if (cell == null) return;
    canvas.drawRRect(
      _cellRect(cell.col, cell.row, weeks.length - 1).inflate(width),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HeatmapGridPainter old) =>
      old.selected?.day != selected?.day ||
      old.hovered?.day != hovered?.day ||
      old.weeks != weeks ||
      old.dayCounts != dayCounts ||
      old.window != window ||
      old.scale != scale ||
      old.palette != palette;
}

/// 顶部月份标签（x 轴粘性）：不随网格滚动，而是按滚动偏移实时重绘。
///
/// 对齐规则：只标「包含当月 1 号」的那一周列（GitHub 语义）；
/// 放不下就跳过而不是 clamp，避免相邻标签重叠。
class _MonthLabelsPainter extends CustomPainter {
  final List<List<DateTime>> weeks;
  final double offset;
  final Color color;

  _MonthLabelsPainter({
    required this.weeks,
    required this.offset,
    required this.color,
  });

  static const double _colW = 17;
  // 相邻标签的最小间距（放不下则跳过当月标签）
  static const double _minGap = 24;

  @override
  void paint(Canvas canvas, Size size) {
    double lastRight = -_minGap;
    for (int i = 0; i < weeks.length; i++) {
      // 该列是否包含当月 1 号
      final hasFirst = weeks[i].any((d) => d.day == 1);
      if (!hasFirst) continue;
      final first = weeks[i].firstWhere((d) => d.day == 1);
      final x = i * _colW - offset;
      if (x < -_colW || x > size.width) continue;
      // 跨年时补上年份，避免只显示月份造成歧义
      final yearChanged = i > 0 && first.year != weeks[i - 1][0].year;
      final label = yearChanged ? '${first.year}/${first.month}' : '${first.month}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 10, color: color),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      // 放不下（与上一个标签贴太近）→ 跳过，绝不重叠
      if (x < lastRight + _minGap) {
        tp.dispose();
        continue;
      }
      tp.paint(canvas, Offset(x, 0));
      lastRight = x + tp.width;
    }
  }

  @override
  bool shouldRepaint(covariant _MonthLabelsPainter old) =>
      old.offset != offset || old.weeks != weeks || old.color != color;
}
