import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../l10n/app_localizations.dart';

/// 统计页面：GitHub 风格热力图 + 总览卡片 + 用量趋势柱状图 + 模型/助手/话题三表。
class UsageStatsPage extends StatefulWidget {
  const UsageStatsPage({super.key});

  @override
  State<UsageStatsPage> createState() => _UsageStatsPageState();
}

/// 时间筛选区间
enum StatsRange {
  all('全部'),
  last30('最近30天'),
  lastMonth('上个月'),
  lastQuarter('上个季度');

  final String label;
  const StatsRange(this.label);

  DateTime? startFor(DateTime now) {
    switch (this) {
      case StatsRange.all:
        return null;
      case StatsRange.last30:
        return now.subtract(const Duration(days: 30));
      case StatsRange.lastMonth:
        return DateTime(now.year, now.month - 1, 1);
      case StatsRange.lastQuarter:
        return DateTime(now.year, now.month - 3, 1);
    }
  }
}

/// 桌面端与移动端共用的统计加载逻辑。
Future<StatsData> loadStatsData(BuildContext context) async {
  final chat = context.read<ChatService>();
  final assistants = context.read<AssistantProvider>().assistants;

  final convos = chat.getAllConversations();
  final messages = <ChatMessage>[];
  for (final c in convos) {
    messages.addAll(chat.getMessages(c.id));
  }

  final prefs = await SharedPreferences.getInstance();
  final launchCount = prefs.getInt('app_launch_count') ?? 0;

  return StatsData(
    conversations: convos,
    messages: messages,
    assistants: assistants,
    launchCount: launchCount,
  );
}

class _UsageStatsPageState extends State<UsageStatsPage> {
  StatsRange _range = StatsRange.all;

  late final Future<StatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = loadStatsData(context);
  }

  void _reload() {
    setState(() {
      _future = loadStatsData(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.settingsPageStats ?? '统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<StatsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('统计加载失败\n${snapshot.error}'));
          }
          final data = snapshot.data!;
          return UsageStatsBody(
            data: data,
            range: _range,
            onRangeChanged: (r) => setState(() => _range = r),
          );
        },
      ),
    );
  }
}

/// 桌面端设置页内嵌的统计面板（复用同一加载与视图主体）。
class DesktopStatsPane extends StatefulWidget {
  const DesktopStatsPane({super.key});

  @override
  State<DesktopStatsPane> createState() => _DesktopStatsPaneState();
}

class _DesktopStatsPaneState extends State<DesktopStatsPane> {
  StatsRange _range = StatsRange.all;

  late final Future<StatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = loadStatsData(context);
  }

  void _reload() {
    setState(() {
      _future = loadStatsData(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<StatsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('统计加载失败\n${snapshot.error}'));
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n?.settingsPageStats ?? '统计',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  onPressed: _reload,
                ),
              ],
            ),
            const SizedBox(height: 8),
            UsageStatsBody(
              data: data,
              range: _range,
              onRangeChanged: (r) => setState(() => _range = r),
            ),
          ],
        );
      },
    );
  }
}

/// 一次加载后的快照数据
class StatsData {
  final List<Conversation> conversations;
  final List<ChatMessage> messages;
  final List<Assistant> assistants;
  final int launchCount;

  const StatsData({
    required this.conversations,
    required this.messages,
    required this.assistants,
    required this.launchCount,
  });
}

// ============================================================================
// 视图
// ============================================================================

class UsageStatsBody extends StatelessWidget {
  final StatsData data;
  final StatsRange range;
  final ValueChanged<StatsRange> onRangeChanged;

  const UsageStatsBody({
    super.key,
    required this.data,
    required this.range,
    required this.onRangeChanged,
  });

  DateTime? get _start => range.startFor(DateTime.now());

  List<ChatMessage> get _msgs {
    final start = _start;
    if (start == null) return data.messages;
    return data.messages.where((m) => m.timestamp.isAfter(start)).toList();
  }

  List<Conversation> get _convos {
    final start = _start;
    if (start == null) return data.conversations;
    return data.conversations.where((c) => c.createdAt.isAfter(start)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _msgs;
    final convos = _convos;

    final totalPrompt = msgs.fold<int>(0, (s, m) => s + (m.promptTokens ?? 0));
    final totalCompletion = msgs.fold<int>(0, (s, m) => s + (m.completionTokens ?? 0));
    final totalCached = msgs.fold<int>(0, (s, m) => s + (m.cachedTokens ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RangeChips(range: range, onChanged: onRangeChanged),
        const SizedBox(height: 16),
        _HeatmapSection(messages: msgs, range: range),
        const SizedBox(height: 16),
        _OverviewSection(
          conversations: convos.length,
          messages: msgs.length,
          promptTokens: totalPrompt,
          completionTokens: totalCompletion,
          cachedTokens: totalCached,
          launchCount: data.launchCount,
        ),
        const SizedBox(height: 16),
        _TrendSection(messages: msgs),
        const SizedBox(height: 16),
        _ModelUsageTable(messages: msgs),
        const SizedBox(height: 16),
        _AssistantUsageTable(
          conversations: convos,
          assistants: data.assistants,
        ),
        const SizedBox(height: 16),
        _TopicUsageTable(conversations: convos),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 区间筛选 chips
// ----------------------------------------------------------------------------

class _RangeChips extends StatelessWidget {
  final StatsRange range;
  final ValueChanged<StatsRange> onChanged;

  const _RangeChips({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in StatsRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: range == r ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    r.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: range == r ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 热力图（GitHub 风格）
// ----------------------------------------------------------------------------

class _HeatmapSection extends StatefulWidget {
  final List<ChatMessage> messages;
  final StatsRange range;

  const _HeatmapSection({required this.messages, required this.range});

  @override
  State<_HeatmapSection> createState() => _HeatmapSectionState();
}

/// 根据筛选范围计算热力图展示窗口（含首尾，日粒度）。
/// [earliest] 为数据最早日期（无数据传 null）。
({DateTime start, DateTime end}) _heatmapWindow(
  StatsRange range,
  DateTime now,
  DateTime? earliest,
) {
  final today = DateTime(now.year, now.month, now.day);
  switch (range) {
    case StatsRange.all:
      // 动态窗口：首次使用只显示最近 4 个月（含当月），随数据增长向前扩展，
      // 上限 53 周（GitHub 惯例）
      final fourMonthsAgo = DateTime(now.year, now.month - 4, 1);
      final startBound = (earliest != null && earliest.isBefore(fourMonthsAgo))
          ? earliest
          : fourMonthsAgo;
      final minStart = today.subtract(const Duration(days: 53 * 7 - 1));
      return (
        start: startBound.isBefore(minStart) ? minStart : startBound,
        end: today,
      );
    case StatsRange.last30:
      return (start: today.subtract(const Duration(days: 29)), end: today);
    case StatsRange.lastMonth:
      return (
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0), // 上月最后一天
      );
    case StatsRange.lastQuarter:
      return (
        start: DateTime(now.year, now.month - 3, 1),
        end: DateTime(now.year, now.month, 0), // 上季度最后一天（上上月末日）
      );
  }
}

class _HeatmapSectionState extends State<_HeatmapSection> {
  /// 点击选中的格子日期，用于显示详情气泡
  DateTime? _selected;

  /// 横向滚动控制器：进入页面时定位到当月（窗口右端）
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后跳到最右端（当月所在位置）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hScroll.hasClients) return;
      _hScroll.jumpTo(_hScroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;

    // 按天聚合消息数（messages 已按筛选范围过滤，与热力图窗口一致）
    final dayCounts = <DateTime, int>{};
    DateTime? earliest;
    for (final m in messages) {
      final d = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      dayCounts[d] = (dayCounts[d] ?? 0) + 1;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }

    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final window = _heatmapWindow(widget.range, now, earliest);

    // 以窗口起点所在周一为首列，生成覆盖整个窗口的周列（每列固定 7 天）
    final firstMonday = window.start.subtract(Duration(days: window.start.weekday - 1));
    final weeks = <List<DateTime>>[];
    var cursor = firstMonday;
    while (!cursor.isAfter(window.end)) {
      weeks.add(List.generate(7, (i) => cursor.add(Duration(days: i))));
      cursor = cursor.add(const Duration(days: 7));
    }

    final maxCount = dayCounts.values.isEmpty ? 1 : dayCounts.values.reduce((a, b) => a > b ? a : b);

    // 5 级调色板：0 空态 / 1~4 透明度递增
    final palette = <Color>[
      cs.surfaceContainerHighest,
      cs.primary.withValues(alpha: 0.3),
      cs.primary.withValues(alpha: 0.5),
      cs.primary.withValues(alpha: 0.75),
      cs.primary,
    ];

    const labelW = 20.0; // 左侧周几标签区（y 轴，固定）
    const labelH = 18.0; // 顶部月份标签行（x 轴，固定）
    const colW = 17.0; // 色块 14 + 间距 3
    const rowH = 17.0;

    return _SectionCard(
      title: '聊天热力图',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // x 轴：月份标签固定顶部，随网格滚动偏移实时重绘（粘性刻度）
          Row(
            children: [
              const SizedBox(width: labelW),
              Expanded(
                child: SizedBox(
                  height: labelH,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _hScroll,
                      builder: (context, _) {
                        final offset = _hScroll.hasClients ? _hScroll.position.pixels : 0.0;
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
          // 固定 x 轴与滚动网格之间的分隔线（地基样式）
          Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
          const SizedBox(height: 8),
          // y 轴（周几标签固定左侧）+ 网格（可横向滚动）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (int i = 0; i < 7; i++)
                    SizedBox(
                      height: rowH,
                      width: labelW,
                      child: Center(
                        child: Text(
                          (i == 0 || i == 2 || i == 4) ? const ['一', '二', '三', '四', '五', '六', '日'][i] : '',
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
                    onTapUp: (d) => _handleTap(d.localPosition, weeks, window),
                    child: SizedBox(
                      width: weeks.length * colW,
                      height: 7 * rowH,
                      child: CustomPaint(
                        painter: _HeatmapPainter(
                          weeks: weeks,
                          dayCounts: dayCounts,
                          maxCount: maxCount,
                          selected: _selected,
                          palette: palette,
                          highlightColor: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 图例：4 级色块（1~4），右对齐（固定不滚动）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('少', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              for (int lv = 1; lv <= 4; lv++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: palette[lv],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: 4),
              Text('多', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  /// 点击命中换算：网格坐标 → (列, 行) → 具体日期；窗口外或空白处取消选中
  void _handleTap(Offset pos, List<List<DateTime>> weeks, ({DateTime start, DateTime end}) window) {
    const colW = 17.0;
    const rowH = 17.0;
    final col = (pos.dx / colW).floor();
    final row = (pos.dy / rowH).floor();
    if (col < 0 || col >= weeks.length || row < 0 || row >= 7) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    final day = weeks[col][row];
    // 周对齐补位产生的窗口外格子不响应
    if (day.isBefore(window.start) || day.isAfter(window.end)) {
      if (_selected != null) setState(() => _selected = null);
      return;
    }
    setState(() => _selected = day);
  }
}

// ----------------------------------------------------------------------------
// 热力图 CustomPainter
// ----------------------------------------------------------------------------

class _HeatmapPainter extends CustomPainter {
  final List<List<DateTime>> weeks;
  final Map<DateTime, int> dayCounts;
  final int maxCount;
  final DateTime? selected;
  final List<Color> palette; // 0 空态 / 1~4 递增
  final Color highlightColor;

  _HeatmapPainter({
    required this.weeks,
    required this.dayCounts,
    required this.maxCount,
    required this.selected,
    required this.palette,
    required this.highlightColor,
  });

  static const double _cell = 14;
  static const double _colW = 17; // 色块 + 间距
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
    // 网格色块（x/y 轴标签已由外部固定渲染，此处仅绘制数据主体）
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

    // 选中格子：描边高亮 + 详情气泡
    final sel = selected;
    if (sel != null) {
      for (int c = 0; c < weeks.length; c++) {
        for (int r = 0; r < 7; r++) {
          if (weeks[c][r] == sel) {
            final rect = Rect.fromLTWH(c * _colW, r * _rowH, _cell, _cell);
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(4)),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = highlightColor,
            );

            final count = dayCounts[sel] ?? 0;
            final text = '${sel.year}-${sel.month.toString().padLeft(2, '0')}-'
                '${sel.day.toString().padLeft(2, '0')} · $count 条消息';
            final tp = TextPainter(
              text: TextSpan(text: text, style: const TextStyle(fontSize: 11, color: Colors.white)),
              textDirection: TextDirection.ltr,
            )..layout();
            const pad = 8.0;
            final bubbleW = tp.width + pad * 2;
            final bubbleH = tp.height + 12;
            var bx = rect.center.dx - bubbleW / 2;
            var by = rect.bottom + 6;
            bx = bx.clamp(0, size.width - bubbleW);
            if (by + bubbleH > size.height) by = rect.top - bubbleH - 6;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(bx, by, bubbleW, bubbleH),
                const Radius.circular(6),
              ),
              Paint()..color = Colors.black87,
            );
            tp.paint(canvas, Offset(bx + pad, by + 6));
            break;
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) {
    return old.selected != selected ||
        old.maxCount != maxCount ||
        old.weeks != weeks ||
        old.dayCounts != dayCounts;
  }
}

/// 顶部月份标签（x 轴，粘性固定）：不随网格滚动，而是按滚动偏移实时重绘，
/// 只绘制当前视口内可见的月份刻度，保证与下方色块列始终对齐。
class _MonthLabelsPainter extends CustomPainter {
  final List<List<DateTime>> weeks;
  final double offset; // 网格横向滚动偏移
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
      // 视口裁剪：只画可见部分
      if (x < -60 || x > size.width + 20) continue;
      // 跨年时标注年份，避免只显示月份造成歧义
      final yearChanged = i > 0 && first.year != weeks[i - 1][0].year;
      final tp = TextPainter(
        text: TextSpan(
          text: yearChanged ? '${first.year}年${first.month}月' : '${first.month}月',
          style: TextStyle(fontSize: 10, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // 右侧边界钳制，避免当月标签被裁切
      final lx = x + tp.width > size.width ? size.width - tp.width : x;
      tp.paint(canvas, Offset(lx, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _MonthLabelsPainter old) {
    return old.offset != offset || old.weeks != weeks || old.color != color;
  }
}

// ----------------------------------------------------------------------------
// 总览卡片
// ----------------------------------------------------------------------------

class _OverviewSection extends StatelessWidget {
  final int conversations;
  final int messages;
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int launchCount;

  const _OverviewSection({
    required this.conversations,
    required this.messages,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedTokens,
    required this.launchCount,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('总对话数', '$conversations'),
      ('总消息数', '$messages'),
      ('输入 Tokens', _fmtTokens(promptTokens)),
      ('输出 Tokens', _fmtTokens(completionTokens)),
      ('缓存 Tokens', _fmtTokens(cachedTokens)),
      ('应用启动次数', '$launchCount'),
    ];
    return _SectionCard(
      title: '总览',
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.5,
        children: [
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtTokens(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

// ----------------------------------------------------------------------------
// 用量趋势（柱状图，按模型分色）
// ----------------------------------------------------------------------------

class _TrendSection extends StatelessWidget {
  final List<ChatMessage> messages;

  const _TrendSection({required this.messages});

  static const _palette = [
    Color(0xFF4C6FFF), // 蓝
    Color(0xFF10B981), // 绿
    Color(0xFFF59E0B), // 橙
    Color(0xFFEF4444), // 红
    Color(0xFF8B5CF6), // 紫
    Color(0xFF06B6D4), // 青
    Color(0xFFEC4899), // 粉
  ];

  /// Y 轴刻度格式化：大数以 K/M 缩写，避免长数字溢出
  String _fmtAxis(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const _SectionCard(title: '用量趋势', child: _EmptyHint(text: '暂无数据'));
    }

    // 时间桶：默认按月；30 天内按天
    final now = DateTime.now();
    final isShort = now.difference(messages.first.timestamp).inDays <= 30;
    final buckets = <DateTime>{};
    final byBucketModel = <DateTime, Map<String, int>>{};
    for (final m in messages) {
      final key = isShort
          ? DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day)
          : DateTime(m.timestamp.year, m.timestamp.month);
      buckets.add(key);
      final model = m.modelId ?? '未知';
      byBucketModel.putIfAbsent(key, () => {}).update(
            model,
            (v) => v + (m.totalTokens ?? 0),
            ifAbsent: () => m.totalTokens ?? 0,
          );
    }
    final sortedBuckets = buckets.toList()..sort();

    // 收集出现的模型并分配颜色
    final modelColors = <String, Color>{};
    final modelOrder = <String>[];
    for (final bucket in sortedBuckets) {
      for (final model in byBucketModel[bucket]!.keys) {
        if (!modelColors.containsKey(model)) {
          modelColors[model] = _palette[modelOrder.length % _palette.length];
          modelOrder.add(model);
        }
      }
    }

    // 最大总量用于归一
    var maxTotal = 0;
    for (final bucket in sortedBuckets) {
      final sum = byBucketModel[bucket]!.values.fold<int>(0, (a, b) => a + b);
      if (sum > maxTotal) maxTotal = sum;
    }
    if (maxTotal == 0) maxTotal = 1;

    // fl_chart 柱状图：每个 bucket 一组柱
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < sortedBuckets.length; i++) {
      final bucket = sortedBuckets[i];
      final rods = <BarChartRodData>[];
      for (final model in modelOrder) {
        final v = byBucketModel[bucket]![model] ?? 0;
        rods.add(BarChartRodData(
          toY: v.toDouble(),
          width: isShort ? 4 : 8,
          color: modelColors[model],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ));
      }
      groups.add(BarChartGroupData(x: i, barRods: rods));
    }

    return _SectionCard(
      title: '用量趋势',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxTotal.toDouble() * 1.2, // 顶部留白
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final model = modelOrder[rodIndex];
                      final date = sortedBuckets[group.x];
                      final label = isShort
                          ? '${date.month}/${date.day}'
                          : '${date.year}-${date.month}';
                      return BarTooltipItem(
                        '$label\n$model\n${rod.toY.round()} tokens',
                        TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            _fmtAxis(value),
                            style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sortedBuckets.length) return const SizedBox.shrink();
                        final date = sortedBuckets[idx];
                        // 稀疏显示，避免重叠
                        if (sortedBuckets.length > 10 && idx % (sortedBuckets.length ~/ 5 + 1) != 0) {
                          return const SizedBox.shrink();
                        }
                        final label = isShort ? '${date.month}/${date.day}' : '${date.month}月';
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.15),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                barGroups: groups,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final model in modelOrder)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: modelColors[model], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(model, style: const TextStyle(fontSize: 11)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 模型使用率表
// ----------------------------------------------------------------------------

class _ModelUsageTable extends StatelessWidget {
  final List<ChatMessage> messages;

  const _ModelUsageTable({required this.messages});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final m in messages) {
      final model = m.modelId ?? '未知';
      counts[model] = (counts[model] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _SectionCard(
      title: '模型使用率',
      child: sorted.isEmpty
          ? const _EmptyHint(text: '暂无数据')
          : Column(
              children: [
                const _TableHeader(left: '模型', right: '消息数'),
                const SizedBox(height: 8),
                for (final e in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PillRow(
                      badge: _badgeFor(e.key),
                      name: e.key,
                      value: '${e.value} 条',
                    ),
                  ),
              ],
            ),
    );
  }

  /// 徽章内容：模型名首字符大写
  String _badgeFor(String name) {
    if (name.isEmpty) return '?';
    return name.characters.first.toUpperCase();
  }
}

// ----------------------------------------------------------------------------
// 助手使用率表
// ----------------------------------------------------------------------------

class _AssistantUsageTable extends StatelessWidget {
  final List<Conversation> conversations;
  final List<Assistant> assistants;

  const _AssistantUsageTable({
    required this.conversations,
    required this.assistants,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{}; // assistantId -> convo count
    for (final c in conversations) {
      final key = c.assistantId ?? '';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String nameFor(String? id) {
      if (id == null || id.isEmpty) return '全局';
      for (final a in assistants) {
        if (a.id == id) return a.name;
      }
      return id;
    }

    return _SectionCard(
      title: '助手使用率',
      child: sorted.isEmpty
          ? const _EmptyHint(text: '暂无数据')
          : Column(
              children: [
                const _TableHeader(left: '助手', right: '话题数'),
                const SizedBox(height: 8),
                for (final e in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PillRow(
                      badge: _badgeFor(nameFor(e.key)),
                      name: nameFor(e.key),
                      value: '${e.value} 个话题',
                    ),
                  ),
              ],
            ),
    );
  }

  /// 徽章内容：助手名首字符
  String _badgeFor(String name) {
    if (name.isEmpty) return '?';
    return name.characters.first;
  }
}

// ----------------------------------------------------------------------------
// 话题内容量表
// ----------------------------------------------------------------------------

class _TopicUsageTable extends StatelessWidget {
  final List<Conversation> conversations;

  const _TopicUsageTable({required this.conversations});

  @override
  Widget build(BuildContext context) {
    final sorted = conversations.toList()
      ..sort((a, b) => b.messageIds.length.compareTo(a.messageIds.length));

    return _SectionCard(
      title: '话题内容量',
      child: sorted.isEmpty
          ? const _EmptyHint(text: '暂无数据')
          : Column(
              children: [
                const _TableHeader(left: '话题', right: '消息数'),
                const SizedBox(height: 8),
                for (final c in sorted.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PillRow(
                      badgeIcon: Icons.chat_bubble_outline,
                      name: c.title.isEmpty ? '（未命名话题）' : c.title,
                      value: '${c.messageIds.length} 条',
                    ),
                  ),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------------------
// 通用组件
// ----------------------------------------------------------------------------

/// 表头：左列名 + 右列名（小字灰色，两端对齐）
class _TableHeader extends StatelessWidget {
  final String left;
  final String right;

  const _TableHeader({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
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

/// 胶囊数据行：图标徽章 + 名称 + 数量
class _PillRow extends StatelessWidget {
  final String? badge;
  final IconData? badgeIcon;
  final String name;
  final String value;

  const _PillRow({
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
