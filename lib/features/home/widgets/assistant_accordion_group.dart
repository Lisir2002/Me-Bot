import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/build_context_l10n.dart';
import 'assistant_avatar.dart';
import 'conversation_tile.dart';

/// 默认助手分组在 SettingsProvider 中的 key（assistantId == null 时使用）
const String kDefaultAssistantKey = '__default__';

/// 助手手风琴分组：单个助手的对话列表，可展开/收起
class AssistantAccordionGroup extends StatefulWidget {
  const AssistantAccordionGroup({
    super.key,
    required this.assistant,
    required this.conversations,
    required this.currentConversationId,
    required this.loadingIds,
    required this.onSelect,
    required this.onShowMenu,
    this.textColor,
    this.overrideExpanded,
  });

  final Assistant? assistant;
  final List<Conversation> conversations;
  final String currentConversationId;
  final Set<String> loadingIds;
  final void Function(String id) onSelect;
  final void Function(Conversation conv, {Offset? anchor}) onShowMenu;

  /// 条目文字颜色（跟随主题 textBase）
  final Color? textColor;

  /// 非空时强制覆盖展开状态（搜索时自动展开匹配分组）
  final bool? overrideExpanded;

  @override
  State<AssistantAccordionGroup> createState() => _AssistantAccordionGroupState();
}

class _AssistantAccordionGroupState extends State<AssistantAccordionGroup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  String get _assistantKey => widget.assistant?.id ?? kDefaultAssistantKey;

  bool get _isExpanded {
    if (widget.overrideExpanded != null) return widget.overrideExpanded!;
    return context.read<SettingsProvider>().isAssistantExpanded(_assistantKey);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 根据展开状态同步动画
    if (_isExpanded) {
      _controller.value = 1.0;
    } else {
      _controller.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(AssistantAccordionGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // overrideExpanded 变化时同步动画
    if (widget.overrideExpanded != oldWidget.overrideExpanded) {
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  void _toggle() {
    // 搜索模式下不允许手动收起（overrideExpanded 强制展开）
    if (widget.overrideExpanded != null) return;
    final settings = context.read<SettingsProvider>();
    final expanded = settings.isAssistantExpanded(_assistantKey);
    if (expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    settings.toggleAssistantExpanded(_assistantKey);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textColor = widget.textColor ?? cs.onSurface;
    final expanded = _isExpanded;

    // 分离置顶与非置顶对话
    final pinned = widget.conversations.where((c) => c.isPinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final unpinned = widget.conversations.where((c) => !c.isPinned).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final displayName = widget.assistant?.name ?? l10n.sideDrawerDefaultAssistant;
    final count = widget.conversations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                buildAssistantAvatar(context, widget.assistant, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Lucide.ChevronDown,
                    size: 16,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 展开内容
        SizeTransition(
          sizeFactor: _heightFactor,
          axisAlignment: -1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 置顶对话
              for (final conv in pinned)
                ConversationTile(
                  conversation: conv,
                  textColor: textColor,
                  selected: conv.id == widget.currentConversationId,
                  loading: widget.loadingIds.contains(conv.id),
                  showPinIcon: true,
                  onTap: () => widget.onSelect(conv.id),
                  onLongPress: () => widget.onShowMenu(conv),
                  onSecondaryTap: (pos) => widget.onShowMenu(conv, anchor: pos),
                ),
              if (pinned.isNotEmpty && unpinned.isNotEmpty)
                const SizedBox(height: 4),
              // 非置顶对话
              for (final conv in unpinned)
                ConversationTile(
                  conversation: conv,
                  textColor: textColor,
                  selected: conv.id == widget.currentConversationId,
                  loading: widget.loadingIds.contains(conv.id),
                  onTap: () => widget.onSelect(conv.id),
                  onLongPress: () => widget.onShowMenu(conv),
                  onSecondaryTap: (pos) => widget.onShowMenu(conv, anchor: pos),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
