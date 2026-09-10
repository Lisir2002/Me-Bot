import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/assistant.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/update_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/snackbar.dart';
import 'conversation_tile.dart';
import 'assistant_accordion_group.dart';

/// 自然排序：有 sortOrder 的按序号升序，无 sortOrder 的按 updatedAt 倒序排前面
List<Conversation> sortConversationsNatural(List<Conversation> list) {
  final manual = list.where((c) => c.sortOrder != null).toList()
    ..sort((a, b) => a.sortOrder!.compareTo(b.sortOrder!));
  final auto = list.where((c) => c.sortOrder == null).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [...auto, ...manual];
}

/// 日期分组数据
class DateGroup {
  final String label;
  final List<Conversation> items;
  DateGroup({required this.label, required this.items});
}

/// 根据日期获取分组标签（今天/昨天/MMM d/MMM d, yyyy）
String dateLabelFromDate(BuildContext context, DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final aDay = DateTime(date.year, date.month, date.day);
  final diff = today.difference(aDay).inDays;
  final l10n = context.l10n;
  if (diff == 0) return l10n.sideDrawerDateToday;
  if (diff == 1) return l10n.sideDrawerDateYesterday;
  final sameYear = now.year == date.year;
  final pattern = sameYear ? l10n.sideDrawerDateShortPattern : l10n.sideDrawerDateFullPattern;
  final fmt = DateFormat(pattern);
  return fmt.format(date);
}

/// 按日期分组（按 updatedAt 的日期），组内按 updatedAt 倒序
List<DateGroup> groupConversationsByDate(BuildContext context, List<Conversation> source) {
  final map = <DateTime, List<Conversation>>{};
  for (final c in source) {
    final d = DateTime(c.updatedAt.year, c.updatedAt.month, c.updatedAt.day);
    map.putIfAbsent(d, () => []).add(c);
  }
  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final k in keys)
      DateGroup(
        label: dateLabelFromDate(context, k),
        items: map[k]!..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      )
  ];
}

/// 核心：对话列表构建器，根据排序模式构建不同列表
class ConversationListBuilder extends StatelessWidget {
  const ConversationListBuilder({
    super.key,
    required this.allConversations,
    required this.currentConversationId,
    required this.loadingConversationIds,
    required this.onSelectConversation,
    required this.onShowChatMenu,
    required this.query,
    this.includeUpdateBanner = false,
    this.embedded = false,
  });

  /// 过滤后的对话列表（自然/时间模式下已按当前助手过滤；助手模式下为全部）
  final List<Conversation> allConversations;
  final String currentConversationId;
  final Set<String> loadingConversationIds;
  final void Function(String id) onSelectConversation;
  final void Function(BuildContext context, Conversation conv, {Offset? anchor}) onShowChatMenu;
  final String query;
  final bool includeUpdateBanner;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : Colors.black;
    final settings = context.watch<SettingsProvider>();
    final sortMode = settings.conversationSortMode;
    final chatService = context.watch<ChatService>();
    final l10n = context.l10n;

    // 搜索过滤
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? allConversations
        : allConversations.where((c) => c.title.toLowerCase().contains(q)).toList();

    // 分离置顶/非置顶
    final pinned = filtered.where((c) => c.isPinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final unpinned = filtered.where((c) => !c.isPinned).toList();

    final children = <Widget>[];

    // 更新横幅
    if (includeUpdateBanner) {
      children.add(const _UpdateBanner());
    }

    // 空状态
    if (filtered.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(
            child: Text(
              l10n.sideDrawerNoConversations,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
      return Column(children: children);
    }

    switch (sortMode) {
      case ConversationSortMode.natural:
        children.addAll(_buildNaturalMode(
          context, cs, textBase, chatService, pinned, unpinned, l10n,
        ));
      case ConversationSortMode.time:
        children.addAll(_buildTimeMode(
          context, cs, textBase, pinned, unpinned, settings, l10n,
        ));
      case ConversationSortMode.byAssistant:
        children.addAll(_buildByAssistantMode(
          context, cs, textBase, pinned, unpinned, settings, q, l10n,
        ));
    }

    return Column(children: children);
  }

  // ---- 模式一：自然排序（支持拖拽）----
  List<Widget> _buildNaturalMode(
    BuildContext context,
    ColorScheme cs,
    Color textBase,
    ChatService chatService,
    List<Conversation> pinned,
    List<Conversation> unpinned,
    dynamic l10n,
  ) {
    final children = <Widget>[];

    // 置顶区
    if (pinned.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
          child: Text(
            l10n.sideDrawerPinnedLabel,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary),
          ).animate().fadeIn(duration: 180.ms).moveY(begin: 4, end: 0, duration: 220.ms, curve: Curves.easeOutCubic),
        ),
      );
      children.add(_buildReorderableSection(
        context: context,
        items: pinned,
        textBase: textBase,
        chatService: chatService,
        keyPrefix: 'pin',
        cs: cs,
      ));
      children.add(const SizedBox(height: 8));
    }

    // 非置顶区（按自然排序）
    final sortedUnpinned = sortConversationsNatural(unpinned);
    if (sortedUnpinned.isNotEmpty) {
      children.add(_buildReorderableSection(
        context: context,
        items: sortedUnpinned,
        textBase: textBase,
        chatService: chatService,
        keyPrefix: 'conv',
        cs: cs,
      ));
    }

    return children;
  }

  Widget _buildReorderableSection({
    required BuildContext context,
    required List<Conversation> items,
    required Color textBase,
    required ChatService chatService,
    required String keyPrefix,
    required ColorScheme cs,
  }) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      itemCount: items.length,
      onReorderStart: (index) => Haptics.medium(),
      onReorderEnd: (index) => Haptics.light(),
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final item = items[oldIndex];
        items.removeAt(oldIndex);
        items.insert(newIndex, item);
        // 归一化 sortOrder
        chatService.reorderConversations(items.map((c) => c.id).toList());
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final double scale = 1.0 + (animation.value * 0.02);
            return Transform.scale(
              scale: scale,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                shadowColor: Colors.black26,
                color: Colors.transparent,
                child: child,
              ),
            );
          },
        );
      },
      itemBuilder: (context, index) {
        final conv = items[index];
        return ConversationTile(
          key: ValueKey('$keyPrefix-${conv.id}'),
          conversation: conv,
          textColor: textBase,
          selected: conv.id == currentConversationId,
          loading: loadingConversationIds.contains(conv.id),
          embedded: embedded,
          showPinIcon: keyPrefix == 'pin',
          onTap: () => onSelectConversation(conv.id),
          onLongPress: () => onShowChatMenu(context, conv),
          onSecondaryTap: (pos) => onShowChatMenu(context, conv, anchor: pos),
        );
      },
    );
  }

  // ---- 模式二：时间排序（按日期分组，不支持拖拽）----
  List<Widget> _buildTimeMode(
    BuildContext context,
    ColorScheme cs,
    Color textBase,
    List<Conversation> pinned,
    List<Conversation> unpinned,
    SettingsProvider settings,
    dynamic l10n,
  ) {
    final children = <Widget>[];

    // 置顶平铺在最上方
    if (pinned.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
          child: Text(
            l10n.sideDrawerPinnedLabel,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary),
          ),
        ),
      );
      for (final conv in pinned) {
        children.add(ConversationTile(
          conversation: conv,
          textColor: textBase,
          selected: conv.id == currentConversationId,
          loading: loadingConversationIds.contains(conv.id),
          embedded: embedded,
          showPinIcon: true,
          onTap: () => onSelectConversation(conv.id),
          onLongPress: () => onShowChatMenu(context, conv),
          onSecondaryTap: (pos) => onShowChatMenu(context, conv, anchor: pos),
        ));
      }
      children.add(const SizedBox(height: 8));
    }

    // 非置顶按日期分组
    final groups = groupConversationsByDate(context, unpinned);
    final showDateHeaders = settings.showChatListDate;
    for (final group in groups) {
      if (showDateHeaders) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
            child: Text(
              group.label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary),
            ),
          ),
        );
      }
      for (final conv in group.items) {
        children.add(ConversationTile(
          conversation: conv,
          textColor: textBase,
          selected: conv.id == currentConversationId,
          loading: loadingConversationIds.contains(conv.id),
          embedded: embedded,
          onTap: () => onSelectConversation(conv.id),
          onLongPress: () => onShowChatMenu(context, conv),
          onSecondaryTap: (pos) => onShowChatMenu(context, conv, anchor: pos),
        ));
      }
      if (showDateHeaders) children.add(const SizedBox(height: 8));
    }

    return children;
  }

  // ---- 模式三：助手分类（手风琴分组）----
  List<Widget> _buildByAssistantMode(
    BuildContext context,
    ColorScheme cs,
    Color textBase,
    List<Conversation> pinned,
    List<Conversation> unpinned,
    SettingsProvider settings,
    String query,
    dynamic l10n,
  ) {
    final children = <Widget>[];
    final ap = context.read<AssistantProvider>();
    final allAssistants = ap.assistants;
    final currentAssistantId = ap.currentAssistantId;

    // 置顶平铺在最上方
    if (pinned.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
          child: Text(
            l10n.sideDrawerPinnedLabel,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary),
          ),
        ),
      );
      for (final conv in pinned) {
        children.add(ConversationTile(
          conversation: conv,
          textColor: textBase,
          selected: conv.id == currentConversationId,
          loading: loadingConversationIds.contains(conv.id),
          embedded: embedded,
          showPinIcon: true,
          onTap: () => onSelectConversation(conv.id),
          onLongPress: () => onShowChatMenu(context, conv),
          onSecondaryTap: (pos) => onShowChatMenu(context, conv, anchor: pos),
        ));
      }
      children.add(const SizedBox(height: 8));
    }

    // 按 assistantId 分组非置顶对话
    final Map<String?, List<Conversation>> grouped = {};
    for (final c in unpinned) {
      grouped.putIfAbsent(c.assistantId, () => []).add(c);
    }

    // 助手排序：当前助手第一，其余按名称字母序
    final assistantIds = grouped.keys.toList();
    assistantIds.sort((a, b) {
      if (a == currentAssistantId) return -1;
      if (b == currentAssistantId) return 1;
      if (a == null) return 1;
      if (b == null) return -1;
      final aName = allAssistants.where((as) => as.id == a).firstOrNull?.name ?? '';
      final bName = allAssistants.where((as) => as.id == b).firstOrNull?.name ?? '';
      return aName.compareTo(bName);
    });

    // 首次进入时自动展开当前助手
    if (query.isEmpty && settings.expandedAssistantIds.isEmpty && currentAssistantId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (settings.expandedAssistantIds.isEmpty) {
          settings.toggleAssistantExpanded(currentAssistantId);
        }
      });
    }

    final searching = query.isNotEmpty;

    for (final aid in assistantIds) {
      final groupItems = grouped[aid]!;
      Assistant? assistant;
      if (aid != null) {
        final idx = allAssistants.indexWhere((a) => a.id == aid);
        if (idx != -1) assistant = allAssistants[idx];
      }

      children.add(
        AssistantAccordionGroup(
          assistant: assistant,
          conversations: groupItems,
          currentConversationId: currentConversationId,
          loadingIds: loadingConversationIds,
          textColor: textBase,
          overrideExpanded: searching ? true : null,
          onSelect: onSelectConversation,
          onShowMenu: (conv, {anchor}) => onShowChatMenu(context, conv, anchor: anchor),
        ),
      );
    }

    return children;
  }
}

/// 更新提示横幅（从 side_drawer 提取）
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final upd = context.watch<UpdateProvider>();
    if (!settings.showAppUpdates) return const SizedBox.shrink();
    final info = upd.available;
    if (upd.checking && info == null) return const SizedBox.shrink();
    if (info == null) return const SizedBox.shrink();
    final url = info.bestDownloadUrl();
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    final ver = info.version;
    final build = info.build;
    final l10n = context.l10n;
    final title = build != null
        ? l10n.sideDrawerUpdateTitleWithBuild(ver, build)
        : l10n.sideDrawerUpdateTitle(ver);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final uri = Uri.parse(url);
            try {
              await launchUrl(uri);
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                showAppSnackBar(
                  context,
                  message: l10n.sideDrawerLinkCopied,
                  type: NotificationType.success,
                );
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.BadgeInfo, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if ((info.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    info.notes!,
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
