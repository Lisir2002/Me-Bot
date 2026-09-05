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
        _HeatmapSection(messages: msgs),
        const SizedBox(height: 16),
        _OverviewSection(
          conversations: convos,
          messages: msgs,
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
    return Wrap(
      spacing: 8,
      children: [
        for (final r in StatsRange.values)
          ChoiceChip(
            label: Text(r.label),
            selected: range == r,
            onSelected: (_) => onChanged(r),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 热力图（GitHub 风格）
// ----------------------------------------------------------------------------

class _HeatmapSection extends StatelessWidget {
  final List<ChatMessage> messages;

  const _HeatmapSection({required this.messages});

  @override
  Widget build(BuildContext context) {
    // 按天聚合消息数
    final dayCounts = <DateTime, int>{};
    for (final m in messages) {
      final d = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      dayCounts[d] = (dayCounts[d] ?? 0) + 1;
    }
    if (dayCounts.isEmpty) {
      return const _SectionCard(title: '聊天热力图', child: _EmptyHint(text: '暂无数据'));
    }

    // 确定展示范围：最近 53 周（GitHub 风格）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 53 * 7 - 1));
    final startWeekday = start.weekday; // 1=Mon..7=Sun
    final weeks = <List<DateTime>>[];
    var cursor = start.subtract(Duration(days: startWeekday - 1));
    while (cursor.isBefore(today) || cursor.isAtSameMomentAs(today)) {
      final week = <DateTime>[];
      for (int i = 0; i < 7; i++) {
        week.add(cursor.add(Duration(days: i)));
      }
      weeks.add(week);
      cursor = cursor.add(const Duration(days: 7));
    }

    final maxCount = dayCounts.values.isEmpty ? 1 : dayCounts.values.reduce((a, b) => a > b ? a : b);

    Color levelColor(int count) {
      final cs = Theme.of(context).colorScheme;
      if (count == 0) return cs.surfaceContainerHighest.withOpacity(0.45);
      final t = count / maxCount;
      return Color.lerp(cs.primary.withOpacity(0.35), cs.primary, t)!;
    }

    return _SectionCard(
      title: '聊天热力图',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 左侧月份标签（简化：每个日期首行）
                for (int i = 0; i < weeks.length; i++)
                  if (weeks[i][0].month != (i > 0 ? weeks[i - 1][0].month : -1))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${weeks[i][0].month}月',
                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 周几标签（仅显示周一/周三/周五）
                Column(
                  children: [
                    for (int i = 0; i < 7; i++)
                      SizedBox(
                        height: 14,
                        child: Text(
                          (i == 0 || i == 2 || i == 4) ? _weekdayLabel(i) : '',
                          style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                for (final week in weeks)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(
                      children: [
                        for (final day in week)
                          Container(
                            width: 13,
                            height: 13,
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: levelColor(dayCounts[day] ?? 0),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('少', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                for (int i = 0; i < 5; i++)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 2),
                    decoration: BoxDecoration(
                      color: levelColor((maxCount * (i + 1) / 5).round()),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 4),
                Text('多', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int i) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return labels[i];
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
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
                maxY: maxTotal.toDouble(),
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
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sortedBuckets.length) return const SizedBox.shrink();
                        final date = sortedBuckets[idx];
                        // 稀疏显示，避免重叠
                        if (sortedBuckets.length > 8 && idx % (sortedBuckets.length ~/ 4 + 1) != 0) {
                          return const SizedBox.shrink();
                        }
                        final label = isShort ? '${date.month}/${date.day}' : '${date.month}月';
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(label, style: const TextStyle(fontSize: 9)),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
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
                for (final e in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text('${e.value} 条', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
    );
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
                for (final e in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            nameFor(e.key),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text('${e.value} 个话题', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
    );
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
                for (final c in sorted.take(20))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text('${c.messageIds.length} 条', style: const TextStyle(fontSize: 13)),
                      ],
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
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
