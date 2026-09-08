import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/stats/stats_aggregator.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/stats_heatmap.dart';
import '../widgets/stats_overview.dart';
import '../widgets/stats_range_bar.dart';
import '../widgets/stats_tables.dart';
import '../widgets/stats_trend.dart';

// ─────────────────────────────────────────────────────────────
// 统计页面入口
//
// 这个文件只负责：取数 + 区间状态 + 组装四个 Section。
// 之前 1312 行全挤在这里（含热力图 Painter、趋势图、三张表），
// 现在按职责拆到 ../widgets/：
//   stats_range_bar.dart  区间选择
//   stats_heatmap.dart    热力图（含 Painter 与详情浮层）
//   stats_overview.dart   总览网格
//   stats_trend.dart      用量趋势（堆叠柱 + 可点图例）
//   stats_tables.dart     模型/助手/话题三表
//   stats_card.dart       卡片、空态、表头、胶囊行等原子
//   stats_l10n.dart       文案收口
//
// ⚠️ UsageStatsBody 自带 ListView(padding 16)，所以 AppPage 传
//    scrollable: false + bodyPadding: zero，不能叠第二层滚动/内边距。
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

  return StatsData(
    conversations: convos,
    messages: messages,
    assistants: assistants,
    launchCount: launchCount,
  );
}

class _UsageStatsPageState extends State<UsageStatsPage> {
  StatsRange _range = StatsRange.all;

  /// 刷新令牌：自增 → `AppPageStates.reloadKey` 变化 → 引擎重新 `load()`。
  int _reloadToken = 0;

  void _reload() => setState(() => _reloadToken++);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return AppPage<StatsData>(
      title: l10n?.settingsPageStats ?? '统计',
      actions: [
        Tooltip(
          message: l10n?.storageRefresh ?? '刷新',
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
      ],
      scrollable: false,
      bodyPadding: AppPagePadding.zero,
      states: AppPageStates<StatsData>(
        load: () => loadStatsData(context),
        reloadKey: _reloadToken,
        buildData: (ctx, data) => UsageStatsBody(
          data: data,
          range: _range,
          onRangeChanged: (r) => setState(() => _range = r),
        ),
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

  late Future<StatsData> _future;

  @override
  void initState() {
    super.initState();
    _future = loadStatsData(context);
  }

  void _reload() => setState(() => _future = loadStatsData(context));

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
          return Center(child: Text('${snapshot.error}'));
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
                  tooltip: l10n?.storageRefresh ?? '刷新',
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

/// 一次加载后的原始数据。
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

/// 统计主体：区间条 + 四个 Section。
///
/// 用 StatefulWidget 缓存聚合结果：切换图例隐藏、滚动、父级重建都不会
/// 重新遍历全量消息，只有 data/range 变化时才重算。
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
  StatsSnapshot? _snapshot;
  StatsData? _cachedData;
  StatsRange? _cachedRange;

  StatsSnapshot get _current {
    if (_snapshot == null ||
        _cachedData != widget.data ||
        _cachedRange != widget.range) {
      _cachedData = widget.data;
      _cachedRange = widget.range;
      _snapshot = StatsSnapshot.compute(
        conversations: widget.data.conversations,
        messages: widget.data.messages,
        assistants: widget.data.assistants,
        launchCount: widget.data.launchCount,
        range: widget.range,
      );
    }
    return _snapshot!;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _current;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatsRangeBar(value: widget.range, onChanged: widget.onRangeChanged),
        const SizedBox(height: 16),
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
  }
}
