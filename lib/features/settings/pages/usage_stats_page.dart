import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/stats/stats_aggregator.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_list_view.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/stats_heatmap.dart';
import '../widgets/stats_overview.dart';
import '../widgets/stats_range_bar.dart';
import '../widgets/stats_tables.dart';
import '../widgets/stats_trend.dart';

// ─────────────────────────────────────────────────────────────
// 统计页面层
//
// 这个文件负责：取数（loadStatsData）+ 区间状态 + 在后台 isolate 计算快照
// （StatsSnapshot.compute）+ 组装四个 Section + CSV 导出。
//
// 子模块仍在 ../widgets/：
//   stats_range_bar.dart  区间选择
//   stats_heatmap.dart    热力图
//   stats_overview.dart   总览网格
//   stats_trend.dart      用量趋势
//   stats_tables.dart     模型/助手/话题三表
//
// ⚠️ compute() 的跨 isolate 约束：
//   HiveObject 持有 BoxBase（内含 StreamController），无法跨 isolate 传递。
//   因此发送前必须用 copyWith() 把活对象 detach 成未挂 Box 的纯拷贝。
// ─────────────────────────────────────────────────────────────

/// 统计页面：热力图 + 总览 + 用量趋势 + 模型/助手/话题三表。
class UsageStatsPage extends StatefulWidget {
  const UsageStatsPage({super.key});

  @override
  State<UsageStatsPage> createState() => _UsageStatsPageState();
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

  // 读取逗号分隔的启动日期串（如 2026-09-01,2026-09-05），解析为日粒度时间。
  final rawDates = prefs.getString('app_launch_dates');
  final launchDates = <DateTime>[];
  if (rawDates != null && rawDates.isNotEmpty) {
    for (final s in rawDates.split(',')) {
      final t = DateTime.tryParse(s.trim());
      if (t != null) {
        launchDates.add(DateTime(t.year, t.month, t.day));
      }
    }
  }

  return StatsData(
    conversations: convos,
    messages: messages,
    assistants: assistants,
    launchCount: launchCount,
    launchDates: launchDates.isEmpty ? null : launchDates,
  );
}

class _UsageStatsPageState extends State<UsageStatsPage> {
  StatsRange _range = StatsRange.all;

  /// 刷新令牌：自增 → `AppPageStates.reloadKey` 变化 → 引擎重新 `load()`。
  int _reloadToken = 0;

  /// 最近一次加载到的原始数据，供 CSV 导出复用。
  StatsData? _lastData;

  void _reload() => setState(() => _reloadToken++);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AppPage<StatsData>.selfScrolling(
      title: l10n.settingsPageStats,
      actions: [
        Tooltip(
          message: l10n.storageRefresh,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.RefreshCw,
            color: cs.onSurface,
            size: 20,
            minSize: 44,
            onTap: _reload,
          ),
        ),
        const SizedBox(width: AppGap.sm),
        Tooltip(
          message: 'Export CSV',
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Download,
            color: cs.onSurface,
            size: 20,
            minSize: 44,
            onTap: _exportCsv,
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      states: AppPageStates<StatsData>(
        load: () => loadStatsData(context),
        reloadKey: _reloadToken,
        buildData: (ctx, data) {
          _lastData = data;
          return UsageStatsBody(
            data: data,
            range: _range,
            onRangeChanged: (r) => setState(() => _range = r),
          );
        },
      ),
    );
  }

  /// 导出当前区间统计为 CSV：确认 → 后台计算 → 写临时文件 → 系统分享。
  Future<void> _exportCsv() async {
    final data = _lastData;
    if (data == null) return;
    await _exportStatsCsv(context, data, _range);
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

  late Future<StatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = loadStatsData(context);
  }

  void _reload() => setState(() => _future = loadStatsData(context));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<StatsData>(
      future: _future,
      builder: (context, snapshot) {
        // 加载中：用骨架屏代替裸转圈。
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppListView(
            topPadding: AppGap.md,
            bottomPadding: AppGap.md,
            children: [_StatsSkeleton()],
          );
        }
        // 错误：用 AppEmpty + 重试按钮，替代原始 Text(error)。
        if (snapshot.hasError) {
          return AppListView(
            topPadding: AppGap.md,
            bottomPadding: AppGap.md,
            children: [
              AppEmpty(
                message: 'Failed to load stats',
                hint: '${snapshot.error}',
                action: FilledButton.tonal(
                  onPressed: _reload,
                  child: Text(context.l10n.commonRetry),
                ),
              ),
            ],
          );
        }
        // 空安全：data 为 null 时显示 AppEmpty，不再用 `!` 强拆。
        final data = snapshot.data;
        if (data == null) {
          return const AppListView(
            topPadding: AppGap.md,
            bottomPadding: AppGap.md,
            children: [AppEmpty(message: 'No data available')],
          );
        }
        return AppListView(
          topPadding: AppGap.md,
          bottomPadding: AppGap.md,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsPageStats,
                    // 设计系统暂无 16/w700 专属 token，保持字号字重、颜色用 cs.onSurface。
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Export CSV',
                  child: IosIconButton(
                    icon: Lucide.Download,
                    haptics: true,
                    color: cs.onSurface,
                    size: 20,
                    minSize: 44,
                    onTap: () => _exportCsv(data),
                  ),
                ),
                const SizedBox(width: AppGap.xs),
                Tooltip(
                  message: l10n.storageRefresh,
                  child: IosIconButton(
                    icon: Lucide.RefreshCw,
                    haptics: true,
                    color: cs.onSurface,
                    size: 20,
                    minSize: 44,
                    onTap: _reload,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppGap.md),
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

  Future<void> _exportCsv(StatsData data) =>
      _exportStatsCsv(context, data, _range);
}

/// 一次加载后的原始数据（列表不可变，防止外部误改）。
class StatsData {
  final List<Conversation> conversations;
  final List<ChatMessage> messages;
  final List<Assistant> assistants;
  final int launchCount;

  /// 记录级启动日期（已归一到日粒度）；为 null 表示无记录，launchCount 用原值。
  final List<DateTime>? launchDates;

  StatsData({
    required List<Conversation> conversations,
    required List<ChatMessage> messages,
    required List<Assistant> assistants,
    required this.launchCount,
    this.launchDates,
  })  : conversations = List.unmodifiable(conversations),
        messages = List.unmodifiable(messages),
        assistants = List.unmodifiable(assistants);
}

// ============================================================================
// 后台 isolate 计算快照
// ============================================================================

/// 跨 isolate 传递的计算参数（纯数据，Hive 对象已 detach）。
class _ComputeParams {
  final List<Conversation> conversations;
  final List<ChatMessage> messages;
  final List<Assistant> assistants;
  final int launchCount;
  final StatsRange range;
  final List<DateTime>? launchDates;

  _ComputeParams({
    required this.conversations,
    required this.messages,
    required this.assistants,
    required this.launchCount,
    required this.range,
    required this.launchDates,
  });
}

/// 顶层 isolate 回调：compute() 要求回调必须是顶层或静态函数，不能是闭包。
StatsSnapshot _runCompute(_ComputeParams p) {
  return StatsSnapshot.compute(
    conversations: p.conversations,
    messages: p.messages,
    assistants: p.assistants,
    launchCount: p.launchCount,
    range: p.range,
    launchDates: p.launchDates,
  );
}

/// 在后台 isolate 中计算快照，避免大数据量聚合阻塞 UI 线程。
Future<StatsSnapshot> _computeSnapshotInIsolate(_ComputeParams p) {
  return compute<_ComputeParams, StatsSnapshot>(_runCompute, p);
}

/// 把附着在 Hive Box 上的活对象 detach 成纯拷贝。
///
/// HiveObject 持有 BoxBase（内含 StreamController），无法跨 isolate 传递；
/// copyWith() 走普通构造函数，产出的新实例未挂在任何 Box 上，字段全是
/// 可序列化的纯 Dart 对象。
List<ChatMessage> _detachMessages(List<ChatMessage> src) =>
    [for (final m in src) m.copyWith()];
List<Conversation> _detachConversations(List<Conversation> src) =>
    [for (final c in src) c.copyWith()];

// ============================================================================
// CSV 导出（移动端 / 桌面端共用）
// ============================================================================

/// CSV 字段转义：含逗号、引号、换行时用双引号包裹，内部引号翻倍。
String _csvEscape(String v) {
  if (v.contains(RegExp(r'[",\r\n]'))) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// 由快照生成 CSV 文本：概览 + 模型排行 + 助手排行 + 话题排行。
String _buildStatsCsv(StatsSnapshot s) {
  final b = StringBuffer();
  b.writeln('Section,Item,Value');
  b.writeln('Overview,Messages,${s.messageCount}');
  b.writeln('Overview,Conversations,${s.conversationCount}');
  b.writeln('Overview,Prompt tokens,${s.promptTokens}');
  b.writeln('Overview,Completion tokens,${s.completionTokens}');
  b.writeln('Overview,Cached tokens,${s.cachedTokens}');
  b.writeln('Overview,Launches,${s.launchCount}');
  b.writeln();
  b.writeln('Models,Name,Messages,Tokens');
  for (final r in s.modelRows) {
    b.writeln('${_csvEscape(r.name)},${r.value},${r.token ?? 0}');
  }
  b.writeln();
  b.writeln('Assistants,Name,Messages,Tokens');
  for (final r in s.assistantRows) {
    b.writeln('${_csvEscape(r.name)},${r.value},${r.token ?? 0}');
  }
  b.writeln();
  b.writeln('Topics,Name,Messages');
  for (final r in s.topicRows) {
    b.writeln('${_csvEscape(r.name)},${r.value}');
  }
  return b.toString();
}

/// 共享导出逻辑：确认 → 后台计算 → 写临时文件 → 系统分享 → SnackBar 反馈。
Future<void> _exportStatsCsv(
  BuildContext context,
  StatsData data,
  StatsRange range,
) async {
  final ok = await AppDialog.confirm(
    context,
    title: 'Export data',
    message: 'Export current stats to a CSV file.',
    confirmText: 'Export',
    cancelText: 'Cancel',
  );
  if (!ok) return;
  try {
    final snapshot = await _computeSnapshotInIsolate(
      _ComputeParams(
        conversations: _detachConversations(data.conversations),
        messages: _detachMessages(data.messages),
        assistants: data.assistants,
        launchCount: data.launchCount,
        range: range,
        launchDates: data.launchDates,
      ),
    );
    final csv = _buildStatsCsv(snapshot);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final file = File('${dir.path}/stats_export_$stamp.csv');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Stats export',
      ),
    );
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: 'Export successful',
      type: NotificationType.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: 'Export failed: $e',
      type: NotificationType.error,
    );
  }
}

// ============================================================================
// 视图
// ============================================================================

/// 统计主体：区间条 + 四个 Section。
///
/// 快照在后台 isolate 异步计算：用 `Future<StatsSnapshot>?` 缓存 future，
/// data/range 变化时重新触发 compute；build 中用 FutureBuilder 渲染。
/// 切换图例隐藏、滚动、父级重建都不会重新触发 isolate 计算。
class UsageStatsBody extends StatefulWidget {
  final StatsData data;
  final StatsRange range;
  final ValueChanged<StatsRange> onRangeChanged;

  const UsageStatsBody({
    super.key,
    required this.data,
    required this.range,
    required this.onRangeChanged,
  });

  @override
  State<UsageStatsBody> createState() => _UsageStatsBodyState();
}

class _UsageStatsBodyState extends State<UsageStatsBody> {
  Future<StatsSnapshot>? _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _rebuildFuture();
  }

  @override
  void didUpdateWidget(covariant UsageStatsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // data/range 变化才重新计算，避免父级单纯重建重复打 isolate。
    if (widget.data != oldWidget.data || widget.range != oldWidget.range) {
      _rebuildFuture();
    }
  }

  void _rebuildFuture() {
    _snapshotFuture = _computeSnapshotInIsolate(
      _ComputeParams(
        conversations: _detachConversations(widget.data.conversations),
        messages: _detachMessages(widget.data.messages),
        assistants: widget.data.assistants,
        launchCount: widget.data.launchCount,
        range: widget.range,
        launchDates: widget.data.launchDates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppListView(
      topPadding: AppGap.md,
      bottomPadding: AppGap.md,
      children: [
        StatsRangeBar(value: widget.range, onChanged: widget.onRangeChanged),
        const SizedBox(height: 16),
        FutureBuilder<StatsSnapshot>(
          future: _snapshotFuture,
          builder: (context, snap) {
            // 加载中：骨架屏。
            if (snap.connectionState != ConnectionState.done) {
              return const _StatsSkeleton();
            }
            // 失败或无数据：AppEmpty，不再裸用 snapshot.data!。
            if (snap.hasError || !snap.hasData) {
              return AppEmpty(
                message: 'Failed to load stats',
                hint: snap.hasError ? '${snap.error}' : null,
              );
            }
            final snapshot = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatsHeatmapCard(snapshot: snapshot),
                const SizedBox(height: 16),
                StatsOverviewCard(snapshot: snapshot),
                const SizedBox(height: 16),
                StatsTrendCard(snapshot: snapshot),
                const SizedBox(height: 16),
                StatsModelTable(snapshot: snapshot),
                const SizedBox(height: 16),
                StatsAssistantTable(snapshot: snapshot),
                const SizedBox(height: 16),
                StatsTopicTable(snapshot: snapshot),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// 骨架屏加载占位
// ============================================================================

/// 统计页加载骨架屏：总览 6 格 + 热力图 + 趋势图 + 三表的灰色占位闪烁。
///
/// 用 AnimatedBuilder + AnimationController 做透明度呼吸效果。
class _StatsSkeleton extends StatefulWidget {
  const _StatsSkeleton();

  @override
  State<_StatsSkeleton> createState() => _StatsSkeletonState();
}

class _StatsSkeletonState extends State<_StatsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _box(double height, {double? width}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final base = cs.onSurface.withValues(alpha: 0.05);
        final hi = cs.onSurface.withValues(alpha: 0.12);
        return Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Color.lerp(base, hi, _controller.value),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 总览 6 格占位（3 列 × 2 行）。
        Wrap(
          spacing: AppGap.sm,
          runSpacing: AppGap.sm,
          children: [
            for (var i = 0; i < 6; i++)
              SizedBox(width: 100, child: _box(72)),
          ],
        ),
        const SizedBox(height: 16),
        // 热力图占位。
        _box(160),
        const SizedBox(height: 16),
        // 趋势图占位。
        _box(180),
        const SizedBox(height: 16),
        // 三张表占位。
        for (var i = 0; i < 3; i++) ...[
          _box(120),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
