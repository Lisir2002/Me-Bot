import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import 'stats_card.dart';
import 'stats_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 总览
//
// 数值一律走 `formatCompactNumber`，与趋势图共用口径；
// label 交给 l10n，不再硬编码中文。
// ─────────────────────────────────────────────────────────────

/// 总览网格：对话数 / 消息数 / 输入 / 输出 / 缓存 / 启动次数。
class StatsOverviewCard extends StatelessWidget {
  final StatsSnapshot snapshot;

  const StatsOverviewCard({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    final items = <(String, String)>[
      (t.overviewConversations, '${snapshot.conversationCount}'),
      (t.overviewMessages, formatCompactNumber(snapshot.messageCount)),
      (t.overviewPromptTokens, formatCompactNumber(snapshot.promptTokens)),
      (t.overviewCompletionTokens, formatCompactNumber(snapshot.completionTokens)),
      (t.overviewCachedTokens, formatCompactNumber(snapshot.cachedTokens)),
      (t.overviewLaunchCount, '${snapshot.launchCount}'),
    ];

    return StatsSectionCard(
      title: t.sectionOverview,
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
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
