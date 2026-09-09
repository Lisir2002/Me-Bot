import 'package:flutter/material.dart';

import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/favicon.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/url_launcher_ext.dart';

/// 「更多」页（LLM 排行榜入口）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar(title: null) → AppPage
///   本页刻意无标题，AppPage.title 现已支持 `String?`，故直接省略该参数
///   （引擎在 title 为 null 且未传 titleWidget 时渲染空标题，视觉等价）。
/// - SingleChildScrollView + padding LTRB(16,0,16,16) → 交给引擎的 ListView，
///   body 直接给 Column，padding 用 AppGap 表达
/// - 魔法数字间距/圆角 → AppGap / AppRadius
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

  Widget title(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppGap.md),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
        ),
      );

    return AppPage(
      // 本页刻意无标题（AppPage.title 已支持 String?，省略即不渲染）
      // 原 SingleChildScrollView 的 LTRB(16, 0, 16, 16)
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, 0, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LeaderBoard section
          title(l10n.morePageLlmLeaderboard),
          Row(
            children: const [
              Expanded(
                child: LeaderBoardItem(
                  url: 'https://lmarena.ai/leaderboard',
                  name: 'LMArena',
                ),
              ),
              SizedBox(width: AppGap.xs),
              Expanded(
                child: LeaderBoardItem(
                  url: 'https://livebench.ai/#/',
                  name: 'LiveBench',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 排行榜卡片（对外导出，勿改名/改构造，外部可能有引用）。
class LeaderBoardItem extends StatelessWidget {
  const LeaderBoardItem({super.key, required this.url, required this.name});

  final String url;
  final String name;

  String _hostOf(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isNotEmpty ? u.host : url;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: cs.outline.withOpacity(0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.openUrl(url),
          child: Padding(
            padding: const EdgeInsets.all(AppGap.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Favicon(url: url, size: 20),
                const SizedBox(height: AppGap.xxs),
                Text(name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppGap.xxs),
                Text(
                  _hostOf(url),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.textTheme.labelSmall?.color?.withOpacity(0.75),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
