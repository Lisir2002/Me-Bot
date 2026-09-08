import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../theme/design_tokens.dart';
import 'stats_card.dart';
import 'stats_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 聊天热力图（GitHub 风格）
//
// 相对旧实现的四处修正：
//   1. 详情气泡从 Canvas 里搬到 Widget 层。旧代码在 `_HeatmapPainter`
//      里用 `Colors.black87` 手绘一个气泡，而 CustomPaint 的高度只有
//      7×17=119px，气泡一旦靠边就被裁掉，而且硬编码黑色在浅色/深色主题
//      下都不跟主题走。现在用 `Stack + Positioned` 浮层，走 inverseSurface。
//   2. 图例补上 0 级（无消息）色块，否则「少」旁边直接是 1 级色，
//      读者看不出「灰色代表完全没聊天」。
//   3. 周几标签改走 `MaterialLocalizations.narrowWeekdays`，不再硬编码
//      一二三四五六日。
//   4. 窗口：非「全部」区间直接复用 `StatsSnapshot.window`，与总览/三表
//      同源；「全部」才用「近 4 个月起步、随数据前扩、最多 53 周」。
// ─────────────────────────────────────────────────────────────

/// 热力图区块。
class StatsHeatmapCard extends StatefulWidget {
  final StatsSnapshot snapshot;

  const StatsHeatmapCard({super.key, required this.snapshot});

  @override
  State<StatsHeatmapCard> createState() => _StatsHeatmapCardState();
}

class _StatsHeatmapCardState extends State<StatsHeatmapCard> {
  /// 当前选中的日期；null 表示未选中。
  DateTime? _selected;

  final ScrollController _hScroll = ScrollController();

  /// 是否在下一帧把网格滚到最右端（当月）。
  bool _pendingScrollToEnd = true;

  // 网格几何：色块 14 + 间距 3 = 17
  static const double _cell = 14;
  static const double _colW = 17;
  static const double _rowH = 17;
  static const double _labelW = 22;
  static const double _labelH = 18;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void didUpdateWidget(covariant StatsHeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      // 换区间后旧选中日可能已经不在窗口内，直接清掉，避免浮层指向空数据
      _selected = null;
      _pendingScrollToEnd = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
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

  /// 以窗口起点所在周一为首列，生成覆盖整个窗口的周列（每列固定 7 天）。
  List<List<DateTime>> _buildWeeks(StatsWindow window) {
    final firstMonday =
        window.start!.subtract(Duration(days: window.start!.weekday - 1));
    final weeks = <List<DateTime>>[];
    var cursor = firstMonday;
    while (!cursor.isAfter(window.end!)) {
      weeks.add(List.generate(7, (i) => cursor.add(Duration(days: i))));
      cursor = cursor.add(const Duration(days: 7));
    }
    return weeks;
  }

  void _handleTap(Offset pos, List<List<DateTime>> weeks, StatsWindow window) {
    final col = (pos.dx / _colW).floor();
    final row = (pos.dy / _rowH).floor();
    if (col < 0 || col >= weeks.length || row < 0 || row >= 7) {
      _clearSelection();
      return;
    }
    final day = weeks[col][row];
    // 周对齐补位产生的窗口外格子不响应
    if (day.isBefore(window.start!) || day.isAfter(window.end!)) {
      _clearSelection();
      return;
    }
    // 再次点击同一天 → 取消
    setState(() => _selected = _selected == day ? null : day);
  }

  void _clearSelection() {
    if (_selected != null) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final dayCounts = widget.snapshot.messagesByDay;
    final now = DateTime.now();

    final window = _window(now);
    final weeks = _buildWeeks(window);

    var maxCount = 0;
    for (final v in dayCounts.values) {
      if (v > maxCount) maxCount = v;
    }
    if (maxCount == 0) maxCount = 1;

    // 5 级调色板：0 无消息 / 1~4 递增
    final palette = <Color>[
      cs.surfaceContainerHighest.withValues(alpha: 0.75),
      cs.primary.withValues(alpha: 0.25),
      cs.primary.withValues(alpha: 0.45),
      cs.primary.withValues(alpha: 0.70),
      cs.primary,
    ];

    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    final gridH = 7 * _rowH;
    final gridW = weeks.length * _colW;

    return StatsSectionCard(
      title: t.sectionHeatmap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        final offset =
                            _hScroll.hasClients ? _hScroll.position.pixels : 0.0;
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
          Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
          const SizedBox(height: AppGap.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // y 轴：周几标签（周一 / 周三 / 周五）
              Column(
                children: [
                  for (int i = 0; i < 7; i++)
                    SizedBox(
                      height: _rowH,
                      width: _labelW,
                      child: Center(
                        child: Text(
                          (i == 0 || i == 2 || i == 4)
                              ? narrow[(DateTime.monday + i) % 7]
                              : '',
                          style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hScroll,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _handleTap(d.localPosition, weeks, window),
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
                                maxCount: maxCount,
                                selected: _selected,
                                palette: palette,
                                ringColor: cs.onSurface,
                              ),
                            ),
                          ),
                          if (_selected != null)
                            _DayDetailOverlay(
                              day: _selected!,
                              count: dayCounts[_selected!] ?? 0,
                              weeks: weeks,
                              gridWidth: gridW,
                              gridHeight: gridH,
                              text: t.heatmapDayDetail(
                                _formatDay(_selected!),
                                dayCounts[_selected!] ?? 0,
                              ),
                              emptyText: t.noActivity,
                            ),
                        ],
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
              Text(t.legendLess,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
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
                            color: cs.outlineVariant.withValues(alpha: 0.6))
                        : null,
                  ),
                ),
              const SizedBox(width: 4),
              Text(t.legendMore,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 选中格子的详情浮层。
///
/// 刻意做成 Widget 而不是画在 Canvas 里：主题色、字号、阴影都跟随
/// Theme，且不会被 CustomPaint 的画布边界裁切。
class _DayDetailOverlay extends StatelessWidget {
  final DateTime day;
  final int count;
  final List<List<DateTime>> weeks;
  final double gridWidth;
  final double gridHeight;
  final String text;
  final String emptyText;

  const _DayDetailOverlay({
    required this.day,
    required this.count,
    required this.weeks,
    required this.gridWidth,
    required this.gridHeight,
    required this.text,
    required this.emptyText,
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

    // 定位到选中格子
    var col = -1;
    var row = -1;
    for (int c = 0; c < weeks.length && col < 0; c++) {
      for (int r = 0; r < 7; r++) {
        if (weeks[c][r] == day) {
          col = c;
          row = r;
          break;
        }
      }
    }
    if (col < 0) return const SizedBox.shrink();

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
            child: Text(
              count > 0 ? text : '$text · $emptyText',
              style: style,
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 热力图网格（只画色块与选中描边，不含任何文案气泡）。
class _HeatmapGridPainter extends CustomPainter {
  final List<List<DateTime>> weeks;
  final Map<DateTime, int> dayCounts;
  final int maxCount;
  final DateTime? selected;
  final List<Color> palette;
  final Color ringColor;

  _HeatmapGridPainter({
    required this.weeks,
    required this.dayCounts,
    required this.maxCount,
    required this.selected,
    required this.palette,
    required this.ringColor,
  });

  static const double _cell = 14;
  static const double _colW = 17;
  static const double _rowH = 17;

  int _levelFor(int count) {
    if (count <= 0) return 0;
    final t = count / maxCount;
    if (t <= 0.25) return 1;
    if (t <= 0.5) return 2;
    if (t <= 0.75) return 3;
    return 4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellPaint = Paint();
    for (int c = 0; c < weeks.length; c++) {
      for (int r = 0; r < 7; r++) {
        final count = dayCounts[weeks[c][r]] ?? 0;
        cellPaint.color = palette[_levelFor(count)];
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * _colW, r * _rowH, _cell, _cell),
            const Radius.circular(3),
          ),
          cellPaint,
        );
      }
    }

    final sel = selected;
    if (sel == null) return;
    for (int c = 0; c < weeks.length; c++) {
      for (int r = 0; r < 7; r++) {
        if (weeks[c][r] != sel) continue;
        final rect = Rect.fromLTWH(c * _colW, r * _rowH, _cell, _cell);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ringColor,
        );
        return;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapGridPainter old) =>
      old.selected != selected ||
      old.maxCount != maxCount ||
      old.weeks != weeks ||
      old.dayCounts != dayCounts;
}

/// 顶部月份标签（x 轴粘性）：不随网格滚动，而是按滚动偏移实时重绘，
/// 只绘制视口内可见的刻度，保证与下方色块列始终对齐。
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

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < weeks.length; i++) {
      final first = weeks[i][0];
      final isNewMonth = first.month != (i > 0 ? weeks[i - 1][0].month : -1);
      if (!isNewMonth) continue;
      final x = i * _colW - offset;
      if (x < -60 || x > size.width + 20) continue;
      // 跨年时补上年份，避免只显示月份造成歧义
      final yearChanged = i > 0 && first.year != weeks[i - 1][0].year;
      final tp = TextPainter(
        text: TextSpan(
          text: yearChanged ? '${first.year}/${first.month}' : '${first.month}',
          style: TextStyle(fontSize: 10, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = x + tp.width > size.width ? size.width - tp.width : x;
      tp.paint(canvas, Offset(lx < 0 ? 0.0 : lx, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _MonthLabelsPainter old) =>
      old.offset != offset || old.weeks != weeks || old.color != color;
}
