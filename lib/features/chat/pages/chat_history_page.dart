// no_raw_alert_dialog 白名单：现有弹窗待迁移到 AppDialog
// no_manual_listview_padding 白名单：现有页面内部 ListView 待迁移到 AppListView
// no_scrollable_false_without_selfscrolling 白名单：内部 ListView 无水平 padding，靠 AppPage bodyPadding(fromLTRB 12,10,12,14) 提供边距
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';

/// 聊天历史页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + 自定义返回键 → AppPage(title/actions/body)，返回键由引擎统一提供
/// - ⚠️ body 内含 Expanded(列表) → 必须 scrollable: false
/// - 空态 → AppEmpty
/// - 魔法数字 → AppGap / AppRadius（无精确 token 的 6/10/14/50 保留字面量或改用等价 token）
///
/// ⚠️ 行为变更（可一键还原）：原页面没有 SafeArea，迁移后由引擎补上，
/// 底部会多出系统安全区内边距。若要完全还原旧观感，给 AppPage 加 `safeArea: false`。
class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key, this.assistantId});
  final String? assistantId;

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> with TickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatService = context.watch<ChatService>();
    final List<Conversation> all = chatService
        .getAllConversations()
        .where((c) =>
            widget.assistantId == null ||
            c.assistantId == widget.assistantId ||
            c.assistantId == null)
        .toList();

    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty ? all : all.where((c) => c.title.toLowerCase().contains(q)).toList();
    final pinned = filtered.where((c) => c.isPinned).toList();
    final others = filtered.where((c) => !c.isPinned).toList();

    return AppPage(
      title: l10n.chatHistoryPageTitle,
      // body 内含 Expanded → 必须 false
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.sm, 10, AppGap.sm, 14),
      actions: [
        IconButton(
          tooltip: l10n.chatHistoryPageSearchTooltip,
          icon: AnimatedIconSwap(
            child: Icon(
              _searching ? Lucide.X : Lucide.Search,
              key: ValueKey(_searching ? 'x' : 'search'),
            ),
          ),
          onPressed: () {
            setState(() {
              if (_searching) _searchCtrl.clear();
              _searching = !_searching;
            });
          },
        ),
        IconButton(
          tooltip: l10n.chatHistoryPageDeleteAllTooltip,
          icon: const Icon(Lucide.Trash2),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.chatHistoryPageDeleteAllDialogTitle),
                content: Text(l10n.chatHistoryPageDeleteAllDialogContent),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.chatHistoryPageCancel)),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l10n.chatHistoryPageDelete,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              final svc = context.read<ChatService>();
              final idsToDelete = svc
                  .getAllConversations()
                  .where((c) => c.assistantId == widget.assistantId)
                  .map((c) => c.id)
                  .toList();
              for (final id in idsToDelete) {
                await svc.deleteConversation(id);
              }
              if (!mounted) return;
              showAppSnackBar(
                context,
                message: l10n.chatHistoryPageDeletedAllSnackbar,
                type: NotificationType.success,
              );
            }
          },
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: kAnim,
            alignment: Alignment.topCenter,
            curve: Curves.easeOutCubic,
            child: PageTransitionSwitcher(
              duration: kAnim,
              reverse: !_searching,
              transitionBuilder: (child, anim, sec) => SharedAxisTransition(
                animation: anim,
                secondaryAnimation: sec,
                transitionType: SharedAxisTransitionType.vertical,
                child: child,
              ),
              child: !_searching
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: l10n.chatHistoryPageSearchHint,
                          filled: true,
                          fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppGap.md, vertical: AppGap.sm),
                          border: OutlineInputBorder(
                            // 50 在本控件高度下会被裁剪成半高，与 AppRadius.circular 等价（胶囊形）
                            borderRadius: BorderRadius.circular(AppRadius.circular),
                            borderSide: const BorderSide(color: Colors.transparent),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.circular),
                            borderSide: const BorderSide(color: Colors.transparent),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.circular),
                            borderSide: BorderSide(color: cs.primary.withOpacity(0.3)),
                          ),
                          prefixIcon:
                              Icon(Lucide.Search, color: cs.onSurface.withOpacity(0.7), size: 18),
                          suffixIcon: (q.isNotEmpty)
                              ? IconButton(
                                  icon: Icon(Lucide.X,
                                      size: 16, color: cs.onSurface.withOpacity(0.7)),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
            ),
          ),

          Expanded(
            child: filtered.isEmpty
                ? AppEmpty(message: l10n.chatHistoryPageNoConversations)
                : ListView(
                    children: [
                      if (pinned.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppGap.xxs, AppGap.xxs, AppGap.xxs, AppGap.xs),
                          child: Text(
                            l10n.chatHistoryPagePinnedSection,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.primary),
                          ),
                        ),
                        for (final c in pinned)
                          _ConversationCard(
                            conversation: c,
                            onTap: () => Navigator.of(context).pop(c.id),
                          ),
                        const SizedBox(height: AppGap.xs),
                      ],
                      for (final c in others)
                        _ConversationCard(
                          conversation: c,
                          onTap: () => Navigator.of(context).pop(c.id),
                        ),
                      const SizedBox(height: AppGap.xs),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation, this.onTap});
  final Conversation conversation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white12 : const Color(0xFFF7F7F9);
    final border = cs.outlineVariant.withOpacity(0.16);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: bg,
        // 14 无精确 token，保留字面量
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              children: [
                // Leading icon/avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Lucide.MessageCircle, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 10),
                // Title and time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppGap.xxs),
                      Row(
                        children: [
                          Icon(Lucide.History, size: 14, color: cs.onSurface.withOpacity(0.6)),
                          const SizedBox(width: 6),
                          Text(
                            _format(context, conversation.updatedAt),
                            style:
                                TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppGap.xs),
                // Pin toggle
                _PinButton(conversation: conversation),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _format(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context);
    final fmt = locale.languageCode == 'zh'
        ? DateFormat('yyyy年M月d日 HH:mm:ss')
        : DateFormat('yyyy-MM-dd HH:mm:ss');
    return fmt.format(dt);
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final pinned = conversation.isPinned;
    return InkResponse(
      onTap: () async {
        await context.read<ChatService>().togglePinConversation(conversation.id);
      },
      radius: 20,
      child: AnimatedContainer(
        duration: kAnim,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppGap.xs),
        decoration: BoxDecoration(
          color: pinned ? cs.primary.withOpacity(0.12) : cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.circular),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedIconSwap(
              child: Icon(
                pinned ? Lucide.PinOff : Lucide.Pin,
                key: ValueKey(pinned ? 'pinOff' : 'pin'),
                size: 16,
                color: pinned ? cs.primary : cs.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedTextSwap(
              text: pinned ? l10n.chatHistoryPagePinned : l10n.chatHistoryPagePin,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: pinned ? cs.primary : cs.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
