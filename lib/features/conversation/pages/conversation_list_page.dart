import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/chat_item.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../shared/widgets/snackbar.dart';

/// 对话列表页 —— 移动端首页。
/// 真实功能（从 SideDrawer 抽逻辑）：搜索、置顶、按日期分组、点击进入 ChatPage、长按管理。
class ConversationListPage extends StatefulWidget {
  const ConversationListPage({super.key});

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final ap = context.watch<AssistantProvider>();
    final l10n = AppLocalizations.of(context)!;

    // 获取当前助手的所有对话（和 SideDrawer 完全一致）
    final currentAssistantId = ap.currentAssistantId;
    final conversations = chatService
        .getAllConversations()
        .where((c) => c.assistantId == currentAssistantId || c.assistantId == null)
        .toList();

    final all = conversations
        .map((c) => ChatItem(id: c.id, title: c.title, created: c.updatedAt))
        .toList();

    final base = _query.trim().isEmpty
        ? all
        : all.where((c) => c.title.toLowerCase().contains(_query.toLowerCase())).toList();

    // 置顶 + 非置顶（和 SideDrawer 一致）
    final pinnedList = base
        .where((c) => (chatService.getConversation(c.id)?.isPinned ?? false))
        .toList()
      ..sort((a, b) => b.created.compareTo(a.created));

    final rest = base
        .where((c) => !(chatService.getConversation(c.id)?.isPinned ?? false))
        .toList();
    final groups = _groupByDate(context, rest);

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mobileTabConversations),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.chatServiceDefaultConversationTitle,
            onPressed: () async {
              final convo = await chatService.createConversation();
              if (mounted) {
                context.push('/conversations/chat/${convo.id}');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框（真实搜索功能）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.chatHistoryPageSearchHint,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // 对话列表
          Expanded(
            child: base.isEmpty
                ? _EmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
                    children: [
                      // 置顶分组
                      if (pinnedList.isNotEmpty) ...[
                        _SectionHeader(text: l10n.chatHistoryPagePinnedSection),
                        for (final c in pinnedList)
                          _ConversationTile(
                            chat: c,
                            pinned: true,
                            onTap: () => context.push('/conversations/chat/${c.id}'),
                            onLongPress: () => _showMenu(context, c),
                          ),
                      ],
                      // 按日期分组
                      for (final g in groups) ...[
                        _SectionHeader(text: g.label),
                        for (final c in g.items)
                          _ConversationTile(
                            chat: c,
                            pinned: false,
                            onTap: () => context.push('/conversations/chat/${c.id}'),
                            onLongPress: () => _showMenu(context, c),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── 日期分组（和 SideDrawer 完全一致的逻辑）──

  List<_ChatGroup> _groupByDate(BuildContext context, List<ChatItem> source) {
    final items = [...source];
    final map = <DateTime, List<ChatItem>>{};
    for (final c in items) {
      final d = DateTime(c.created.year, c.created.month, c.created.day);
      map.putIfAbsent(d, () => []).add(c);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        _ChatGroup(
          label: _dateLabel(context, k),
          items: (map[k]!..sort((a, b) => b.created.compareTo(a.created))),
        ),
    ];
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(aDay).inDays;
    if (diff == 0) return l10n.sideDrawerDateToday;
    if (diff == 1) return l10n.sideDrawerDateYesterday;
    final sameYear = now.year == date.year;
    final fmt = DateFormat(
      sameYear ? l10n.sideDrawerDateShortPattern : l10n.sideDrawerDateFullPattern,
    );
    return fmt.format(date);
  }

  // ── 长按菜单（重命名 / 置顶 / 删除）──

  Future<void> _showMenu(BuildContext context, ChatItem chat) async {
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.read<ChatService>();
    final convo = chatService.getConversation(chat.id);
    final isPinned = convo?.isPinned ?? false;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.sideDrawerMenuRename),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(isPinned ? l10n.sideDrawerMenuUnpin : l10n.sideDrawerMenuPin),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l10n.sideDrawerMenuDelete, style: const TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    switch (selected) {
      case 'rename':
        await _rename(context, chat);
        break;
      case 'pin':
        await chatService.togglePinConversation(chat.id);
        break;
      case 'delete':
        await _delete(context, chat);
        break;
    }
  }

  Future<void> _rename(BuildContext context, ChatItem chat) async {
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.read<ChatService>();
    final controller = TextEditingController(text: chat.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.conversationRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.sideDrawerCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.sideDrawerSave),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await chatService.renameConversation(chat.id, result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(BuildContext context, ChatItem chat) async {
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.read<ChatService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.conversationDeleteConfirmTitle),
        content: Text(l10n.conversationDeleteConfirmContent(chat.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.sideDrawerCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.sideDrawerMenuDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await chatService.deleteConversation(chat.id);
      if (mounted) {
        showAppSnackBar(
          context,
          message: l10n.conversationDeletedSnackbar,
          type: NotificationType.success,
        );
        setState(() {});
      }
    }
  }
}

// ── 辅助 widget ──

class _ConversationTile extends StatelessWidget {
  final ChatItem chat;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConversationTile({
    required this.chat,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (pinned) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.push_pin, size: 14, color: cs.primary.withOpacity(0.7)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withOpacity(0.5),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.chat_bubble_outline, size: 32, color: cs.primary.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.chatHistoryPageNoConversations,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.7),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.conversationListEmptyHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.5),
                ),
          ),
        ],
      ),
    );
  }
}

class _ChatGroup {
  final String label;
  final List<ChatItem> items;
  _ChatGroup({required this.label, required this.items});
}
