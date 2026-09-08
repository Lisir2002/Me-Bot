import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../theme/design_tokens.dart';
import 'stats_card.dart';
import 'stats_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 三张用量排行表
//
// 数据来自 `StatsSnapshot`（已排好序），这里只负责渲染。
// 模型名 / 助手名 / 话题名都做了占位翻译：
//   · 空 modelId        → 「未知」
//   · 空 assistantId    → 「全局」
//   · 空话题标题        → 「（未命名话题）」
// ─────────────────────────────────────────────────────────────

/// 模型使用率：按消息条数排行。
class StatsModelTable extends StatelessWidget {
  final StatsSnapshot snapshot;

  const StatsModelTable({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final rows = snapshot.modelRows;

    return StatsSectionCard(
      title: t.modelUsage,
      child: rows.isEmpty
          ? StatsEmptyHint(text: t.noData)
          : Column(
              children: [
                StatsTableHeader(left: t.colModel, right: t.colMessages),
                const SizedBox(height: AppGap.xs),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StatsPillRow(
                      badge: _badge(r, t),
                      name: _name(r, t),
                      value: t.messageCount(r.value),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _name(UsageRow r, StatsL10n t) =>
      r.name == StatsSnapshot.unknownModelKey ? t.unknownModel : r.name;

  static String _badge(UsageRow r, StatsL10n t) {
    final name = _name(r, t);
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }
}

/// 助手使用率：按该助手下的话题数排行。
class StatsAssistantTable extends StatelessWidget {
  final StatsSnapshot snapshot;

  const StatsAssistantTable({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final rows = snapshot.assistantRows;

    return StatsSectionCard(
      title: t.assistantUsage,
      child: rows.isEmpty
          ? StatsEmptyHint(text: t.noData)
          : Column(
              children: [
                StatsTableHeader(left: t.colAssistant, right: t.colTopicCount),
                const SizedBox(height: AppGap.xs),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StatsPillRow(
                      badge: _badge(r, t),
                      name: _name(r, t),
                      value: t.topicCount(r.value),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _name(UsageRow r, StatsL10n t) =>
      r.name == StatsSnapshot.globalAssistantKey ? t.globalAssistant : r.name;

  static String _badge(UsageRow r, StatsL10n t) {
    final name = _name(r, t);
    return name.isEmpty ? '?' : name.characters.first;
  }
}

/// 话题内容量：按话题内消息条数排行（取前 20）。
class StatsTopicTable extends StatelessWidget {
  final StatsSnapshot snapshot;

  const StatsTopicTable({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final rows = snapshot.topicRows;

    return StatsSectionCard(
      title: t.topicUsage,
      child: rows.isEmpty
          ? StatsEmptyHint(text: t.noData)
          : Column(
              children: [
                StatsTableHeader(left: t.colTopic, right: t.colMessages),
                const SizedBox(height: AppGap.xs),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StatsPillRow(
                      badgeIcon: Icons.chat_bubble_outline,
                      name: _name(r, t),
                      value: t.messageCount(r.value),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _name(UsageRow r, StatsL10n t) =>
      r.name == StatsSnapshot.unnamedTopicKey ? t.unnamedTopic : r.name;
}
