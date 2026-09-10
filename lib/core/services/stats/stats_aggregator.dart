import 'package:characters/characters.dart';

import '../../models/assistant.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';

// ─────────────────────────────────────────────────────────────
// 统计页数据层
//
// 旧实现把「过滤 + 聚合」散落在各个 Section 的 build 里：
//   · 热力图自己遍历一遍 messages 算 dayCounts
//   · 趋势图自己遍历一遍算桶，还用 `messages.first` 判断跨度
//   · 三张表各自再遍历一遍
// 结果是 O(4N) 且每次重建都重算，更要命的是各处口径不一致。
//
// 这里收敛成一次 `StatsSnapshot.compute()`：
//   · 统一时间窗口（旧 `StatsRange.startFor` 只有起点，没有终点，
//     导致「上个月」会把本月数据也算进总览/趋势，而热力图用的是
//     [上月1日, 上月最后一天]，各卡片数字对不上）
//   · 趋势桶粒度用真实 min~max 跨度判断，不再依赖 messages 的排列顺序
//   · 模型列表按名称排序，保证配色在任何区间下都稳定
//
// v2 修复/增强：
//   · conversationCount 改为「窗口内有消息的会话数」（按 conversationId 去重）
//   · 模型/助手排行按 token 聚合排序，value 仍保留消息条数
//   · 助手排行通过 conversationId → assistantId 映射聚合
//   · launchCount 支持按 launchDates 过滤
//   · StatsData 列表不可变、topicRows 可配上上限
//   · 周期对比：compute 同时计算上一周期快照挂到 previous
// ─────────────────────────────────────────────────────────────

/// 统计时间区间。
enum StatsRange {
  all,
  last30,
  lastMonth,
  lastQuarter,
}

/// 区间对应的时间窗口（日粒度，含首尾）。
///
/// `start`/`end` 为 null 表示不限（仅 [StatsRange.all]）。
class StatsWindow {
  final DateTime? start;
  final DateTime? end;

  const StatsWindow({this.start, this.end});

  /// [day] 必须已归一到日粒度。
  bool contains(DateTime day) {
    final s = start;
    final e = end;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }
}

/// 区间 → 时间窗口的映射。
extension StatsRangeWindow on StatsRange {
  StatsWindow windowFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case StatsRange.all:
        return const StatsWindow();
      case StatsRange.last30:
        return StatsWindow(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case StatsRange.lastMonth:
        return StatsWindow(
          start: DateTime(now.year, now.month - 1, 1),
          end: DateTime(now.year, now.month, 0), // 上月最后一天
        );
      case StatsRange.lastQuarter:
        // 最近 3 个自然月（不含当月）：上月末往前推 3 个月的 1 号
        return StatsWindow(
          start: DateTime(now.year, now.month - 3, 1),
          end: DateTime(now.year, now.month, 0),
        );
    }
  }

  /// 上一周期窗口（与当前窗口等长、紧邻其前）。
  ///
  /// [StatsRange.all] 无上一周期，返回空窗口（调用方不应使用）。
  StatsWindow previousWindowFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case StatsRange.all:
        return const StatsWindow();
      case StatsRange.last30:
        // 当前窗口 [today-29, today]，上一窗口 [today-59, today-30]
        return StatsWindow(
          start: today.subtract(const Duration(days: 59)),
          end: today.subtract(const Duration(days: 30)),
        );
      case StatsRange.lastMonth:
        // 当前 [上月1日, 上月末]，上一窗口为上上月整月
        return StatsWindow(
          start: DateTime(now.year, now.month - 2, 1),
          end: DateTime(now.year, now.month - 1, 0),
        );
      case StatsRange.lastQuarter:
        // 当前为最近 3 个自然月，上一窗口为再往前 3 个自然月
        return StatsWindow(
          start: DateTime(now.year, now.month - 6, 1),
          end: DateTime(now.year, now.month - 3, 0),
        );
    }
  }
}

/// 趋势图的一个时间桶。
class TrendBucket {
  final DateTime date;

  /// 桶内各模型的 token 用量（按天或按月聚合）。
  final Map<String, int> byModel;

  const TrendBucket({required this.date, required this.byModel});

  /// 只统计 [visible] 里的模型（图例可隐藏模型）。
  int totalFor(Iterable<String> visible) {
    var s = 0;
    for (final m in visible) {
      s += byModel[m] ?? 0;
    }
    return s;
  }

  int get total => byModel.values.fold(0, (a, b) => a + b);
}

/// 趋势序列：按天或按月聚合，各模型堆叠。
class TrendSeries {
  final List<TrendBucket> buckets;

  /// true = 按天聚合（数据跨度 ≤ 31 天）；false = 按月聚合。
  final bool daily;

  /// 参与展示的模型名，按名称排序保证配色稳定。
  final List<String> models;

  final int maxTotal;

  const TrendSeries({
    required this.buckets,
    required this.daily,
    required this.models,
    required this.maxTotal,
  });

  bool get isEmpty => buckets.isEmpty;
}

/// 用量排行行（模型/助手/话题三表共用）。
class UsageRow {
  final String name;

  /// 消息条数（保留字段）。
  final int value;

  /// token 总量（模型/助手表有值，话题表为 null）。
  final int? token;

  /// 徽章文字（首字符）；为 null 时用图标徽章。
  final String? badge;

  const UsageRow({
    required this.name,
    required this.value,
    this.token,
    this.badge,
  });
}

/// 一次统计快照：给定区间后**一次性**算好所有模块需要的数据。
class StatsSnapshot {
  final StatsRange range;
  final StatsWindow window;

  final int messageCount;
  final int conversationCount;
  final int launchCount;

  /// launchDates 非空时为 true，表示 launchCount 已按窗口过滤（UI 据此标注）。
  final bool launchCountFiltered;

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;

  /// 按天聚合的消息数（key 已归一到日粒度）。
  final Map<DateTime, int> messagesByDay;

  /// 窗口内的原始消息列表（日粒度筛选后的子集）。
  ///
  /// 热力图点选某一天时需要据此算当日 token / 模型分布 / 助手分布，
  /// 故在聚合时一并保留引用。窗口内消息量可控，内存开销可接受。
  final List<ChatMessage> windowMessages;

  /// conversationId → assistantId 映射（用全量会话构建）。
  ///
  /// 与 `windowMessages` 配合：点选某天后按消息的 conversationId 反查助手，
  /// 再用 [assistants] 解析出展示名。
  final Map<String, String> convoToAssistant;

  /// 全量助手列表（用于 assistantId → 名称解析）。
  final List<Assistant> assistants;

  /// 数据中的最早日期（用于「全部」区间动态窗口），无数据为 null。
  final DateTime? earliestDay;

  final TrendSeries trend;

  final List<UsageRow> modelRows;
  final List<UsageRow> assistantRows;
  final List<UsageRow> topicRows;

  /// 上一周期快照，用于周期对比；[StatsRange.all] 区间为 null。
  final StatsSnapshot? previous;

  const StatsSnapshot({
    required this.range,
    required this.window,
    required this.messageCount,
    required this.conversationCount,
    required this.launchCount,
    required this.launchCountFiltered,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedTokens,
    required this.messagesByDay,
    required this.windowMessages,
    required this.convoToAssistant,
    required this.assistants,
    required this.earliestDay,
    required this.trend,
    required this.modelRows,
    required this.assistantRows,
    required this.topicRows,
    this.previous,
  });

  /// 计算快照。
  ///
  /// [now] 可注入固定时间，便于测试与避免多次 `DateTime.now()` 抖动。
  /// [launchDates] 提供时，launchCount 会按窗口过滤计数；为 null 时直接用
  /// 传入的 [launchCount] 原值。[topicLimit] 限制话题表行数。
  factory StatsSnapshot.compute({
    required List<Conversation> conversations,
    required List<ChatMessage> messages,
    required List<Assistant> assistants,
    required int launchCount,
    required StatsRange range,
    List<DateTime>? launchDates,
    int topicLimit = 20,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final window = range.windowFor(n);

    // conversationId → assistantId 映射（用全量会话构建：窗口内消息可能
    // 属于更早创建、不在本窗口内的会话）。
    final convoToAssistant = <String, String>{};
    for (final c in conversations) {
      convoToAssistant[c.id] = c.assistantId ?? '';
    }

    // ---- 按窗口过滤 ----
    final msgs = _filterMsgs(messages, window);
    final convos = _filterConvos(conversations, window);

    // ---- launchCount 是否按窗口过滤 ----
    final filtered = launchDates != null;
    int countLaunches(StatsWindow w) {
      var c = 0;
      for (final d in launchDates!) {
        if (w.contains(_dayOf(d))) c++;
      }
      return c;
    }

    // 先算上一周期（避免当前快照建好后再回溯）。
    StatsSnapshot? previous;
    if (range != StatsRange.all) {
      final prevWindow = range.previousWindowFor(n);
      final prevMsgs = _filterMsgs(messages, prevWindow);
      final prevConvos = _filterConvos(conversations, prevWindow);
      previous = _computeInternal(
        range: range,
        window: prevWindow,
        msgs: prevMsgs,
        windowConvos: prevConvos,
        convoToAssistant: convoToAssistant,
        assistants: assistants,
        launchCount: filtered ? countLaunches(prevWindow) : launchCount,
        launchCountFiltered: filtered,
        topicLimit: topicLimit,
        // 上一周期不再嵌套 previous，避免递归。
        previous: null,
      );
    }

    return _computeInternal(
      range: range,
      window: window,
      msgs: msgs,
      windowConvos: convos,
      convoToAssistant: convoToAssistant,
      assistants: assistants,
      launchCount: filtered ? countLaunches(window) : launchCount,
      launchCountFiltered: filtered,
      topicLimit: topicLimit,
      previous: previous,
    );
  }

  /// 已过滤窗口数据后的实际聚合（当前/上一周期共用，避免无限递归）。
  static StatsSnapshot _computeInternal({
    required StatsRange range,
    required StatsWindow window,
    required List<ChatMessage> msgs,
    required List<Conversation> windowConvos,
    required Map<String, String> convoToAssistant,
    required List<Assistant> assistants,
    required int launchCount,
    required bool launchCountFiltered,
    required int topicLimit,
    required StatsSnapshot? previous,
  }) {
    // conversationCount：窗口内有消息的会话数（按 conversationId 去重）。
    final convoIds = <String>{};
    for (final m in msgs) {
      convoIds.add(m.conversationId);
    }

    // ---- 按天聚合 + token 汇总（一次遍历） ----
    final byDay = <DateTime, int>{};
    var prompt = 0;
    var completion = 0;
    var cached = 0;
    DateTime? earliest;
    for (final m in msgs) {
      final d = _dayOf(m.timestamp);
      byDay[d] = (byDay[d] ?? 0) + 1;
      prompt += m.promptTokens ?? 0;
      completion += m.completionTokens ?? 0;
      cached += m.cachedTokens ?? 0;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }

    return StatsSnapshot(
      range: range,
      window: window,
      messageCount: msgs.length,
      conversationCount: convoIds.length,
      launchCount: launchCount,
      launchCountFiltered: launchCountFiltered,
      promptTokens: prompt,
      completionTokens: completion,
      cachedTokens: cached,
      messagesByDay: byDay,
      windowMessages: msgs,
      convoToAssistant: convoToAssistant,
      assistants: assistants,
      earliestDay: earliest,
      trend: _computeTrend(msgs),
      modelRows: _computeModelRows(msgs),
      assistantRows: _computeAssistantRows(
        msgs,
        convoToAssistant,
        assistants,
      ),
      topicRows: _computeTopicRows(windowConvos, topicLimit),
      previous: previous,
    );
  }

  static List<ChatMessage> _filterMsgs(
    List<ChatMessage> messages,
    StatsWindow window,
  ) {
    final out = <ChatMessage>[];
    for (final m in messages) {
      if (window.contains(_dayOf(m.timestamp))) out.add(m);
    }
    return out;
  }

  static List<Conversation> _filterConvos(
    List<Conversation> conversations,
    StatsWindow window,
  ) {
    final out = <Conversation>[];
    for (final c in conversations) {
      if (!window.contains(_dayOf(c.createdAt))) continue;
      out.add(c);
    }
    return out;
  }

  /// 归一到日粒度。
  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 一条消息的计费 token 数。
  ///
  /// 老消息只落了 `totalTokens`，新消息才有 prompt/completion 分项
  /// （见 `ChatMessage` 字段注释），所以以 totalTokens 为主、分项为辅。
  static int _tokensOf(ChatMessage m) {
    final t = m.totalTokens;
    if (t != null && t > 0) return t;
    return (m.promptTokens ?? 0) + (m.completionTokens ?? 0);
  }

  /// 一条消息的计费 token 数（公开版，供展示层如热力图日详情复用）。
  static int tokenOf(ChatMessage m) => _tokensOf(m);

  static String _modelOf(ChatMessage m) {
    final id = m.modelId?.trim();
    if (id == null || id.isEmpty) return unknownModelKey;
    return id;
  }

  /// 模型名为空时的占位 key（展示层负责翻译成文案）。
  static const String unknownModelKey = '__stats_unknown_model__';

  /// 时间桶：跨度 ≤31 天按天，否则按月。
  ///
  /// 旧实现用 `messages.first.timestamp` 判断跨度，但 messages 是遍历会话
  /// 拼接出来的、不保证时序，`first` 未必最早，会导致桶粒度判错。
  /// 这里改用真实的 min~max 跨度。
  static TrendSeries _computeTrend(List<ChatMessage> msgs) {
    if (msgs.isEmpty) {
      return const TrendSeries(
        buckets: [],
        daily: true,
        models: [],
        maxTotal: 0,
      );
    }

    DateTime? min;
    DateTime? max;
    for (final m in msgs) {
      final d = _dayOf(m.timestamp);
      if (min == null || d.isBefore(min)) min = d;
      if (max == null || d.isAfter(max)) max = d;
    }
    final spanDays = max!.difference(min!).inDays;
    final daily = spanDays <= 31;

    final byBucket = <DateTime, Map<String, int>>{};
    final modelSet = <String>{};
    for (final m in msgs) {
      final t = m.timestamp;
      final key = daily ? _dayOf(t) : DateTime(t.year, t.month);
      final model = _modelOf(m);
      modelSet.add(model);
      final bucket = byBucket.putIfAbsent(key, () => <String, int>{});
      bucket[model] = (bucket[model] ?? 0) + _tokensOf(m);
    }

    // 模型按名称排序：保证同一模型在任何区间下拿到同一种颜色，
    // 避免切换区间后图例配色跳变。
    final models = modelSet.toList()..sort();
    final sortedKeys = byBucket.keys.toList()..sort();

    var maxTotal = 0;
    final buckets = <TrendBucket>[];
    for (final k in sortedKeys) {
      final b = TrendBucket(date: k, byModel: Map<String, int>.from(byBucket[k]!));
      if (b.total > maxTotal) maxTotal = b.total;
      buckets.add(b);
    }

    return TrendSeries(
      buckets: buckets,
      daily: daily,
      models: models,
      maxTotal: maxTotal,
    );
  }

  /// 模型排行：按 token 聚合降序，value 保留消息条数。
  static List<UsageRow> _computeModelRows(List<ChatMessage> msgs) {
    final counts = <String, int>{};
    final tokens = <String, int>{};
    for (final m in msgs) {
      final model = _modelOf(m);
      counts[model] = (counts[model] ?? 0) + 1;
      tokens[model] = (tokens[model] ?? 0) + _tokensOf(m);
    }
    // 按 token 降序。
    final sorted = tokens.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted)
        UsageRow(
          name: e.key,
          value: counts[e.key] ?? 0,
          token: e.value,
          badge: e.key.isEmpty ? '?' : e.key.characters.first.toUpperCase(),
        ),
    ];
  }

  /// 助手排行：通过 conversationId → assistantId 映射，按 token 聚合降序，
  /// value 保留消息条数。
  static List<UsageRow> _computeAssistantRows(
    List<ChatMessage> msgs,
    Map<String, String> convoToAssistant,
    List<Assistant> assistants,
  ) {
    final counts = <String, int>{};
    final tokens = <String, int>{};
    for (final m in msgs) {
      final key = convoToAssistant[m.conversationId] ?? '';
      counts[key] = (counts[key] ?? 0) + 1;
      tokens[key] = (tokens[key] ?? 0) + _tokensOf(m);
    }
    // 按 token 降序。
    final sorted = tokens.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String nameFor(String id) {
      if (id.isEmpty) return globalAssistantKey;
      for (final a in assistants) {
        if (a.id == id) return a.name;
      }
      return id;
    }

    return [
      for (final e in sorted)
        UsageRow(
          name: nameFor(e.key),
          value: counts[e.key] ?? 0,
          token: e.value,
          badge: (() {
            final n = nameFor(e.key);
            return n.isEmpty ? '?' : n.characters.first;
          })(),
        ),
    ];
  }

  /// 未绑定助手时的占位 key（展示层负责翻译成「全局」）。
  static const String globalAssistantKey = '__stats_global_assistant__';

  /// 话题排行：按会话消息数排序，取前 [limit] 条。
  static List<UsageRow> _computeTopicRows(
    List<Conversation> convos, [
    int limit = 20,
  ]) {
    final sorted = convos.toList()
      ..sort((a, b) => b.messageIds.length.compareTo(a.messageIds.length));
    return [
      for (final c in sorted.take(limit))
        UsageRow(
          name: c.title.isEmpty ? unnamedTopicKey : c.title,
          value: c.messageIds.length,
        ),
    ];
  }

  /// 话题无标题时的占位 key。
  static const String unnamedTopicKey = '__stats_unnamed_topic__';
}
