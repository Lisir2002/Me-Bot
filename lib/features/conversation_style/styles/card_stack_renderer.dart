import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/message_animations.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 04: 卡片堆叠式渲染器
///
/// 布局特点：
/// - 每条消息是一个带阴影的 Card 组件，视觉层次分明
/// - 卡片头部（Card header）显示头像 + 角色名 + 时间
/// - 用户消息卡片左侧蓝色边框标记
/// - 助手消息卡片左侧绿色边框标记
/// - 同角色连续卡片间距收紧（~8px），不同角色拉开（~16px），阴影逐层微增
/// - 连续工具调用用 ToolGroupCard 聚合（卡片内嵌卡片）
/// - 思考部分用增强 ThinkingPartRenderer（流式自动展开）
/// - 用户引用回复用 QuoteRefWidget 置于卡片顶部
/// - 流式中的助手卡片在末尾追加 StreamingCursor
/// - 图片/文件附件在卡片内用圆角缩略图展示
///
/// 适用场景：文件分享、图片密集、视觉驱动
class CardStackRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.cardStack;

  /// 智能滚动控制器（懒初始化，随渲染器生命周期释放）
  SmartScrollController? _scrollCtrl;
  /// 是否显示"跳转到底部"按钮
  final ValueNotifier<bool> _showJump = ValueNotifier<bool>(false);

  @override
  void onDetach() {
    _scrollCtrl?.dispose();
    _scrollCtrl = null;
    super.onDetach();
  }

  @override
  Widget build(BuildContext context) {
    _scrollCtrl ??= SmartScrollController()
      ..onUserScrolledAway = (away) => _showJump.value = away;
    final ctrl = _scrollCtrl!;
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        // 新消息到达且用户在底部附近时，自动平滑跟随到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctrl.hasClients && ctrl.shouldAutoScroll) {
            ctrl.animateTo(
              ctrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        return Stack(
          children: [
            ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                // 上一条是否同角色（决定卡片间距是否收紧）
                final prevSameRole =
                    index > 0 && messages[index - 1].role == message.role;
                // 计算同角色连续层数，用于阴影逐层微增
                int layer = 0;
                for (int j = index - 1;
                    j >= 0 && messages[j].role == message.role;
                    j--) {
                  layer++;
                }
                final w = _buildMessageCard(
                  context,
                  message,
                  messages,
                  prevSameRole: prevSameRole,
                  layer: layer,
                );
                // 仅最新一条消息播放底部滑入 + 淡入
                final isLast = index == messages.length - 1;
                return isLast ? MessageSlideIn(child: w) : w;
              },
            ),
            // 上翻后显示"跳转到底部"悬浮按钮
            Positioned(
              right: 12,
              bottom: 12,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showJump,
                builder: (context, show, _) => show
                    ? FloatingActionButton.small(
                        onPressed: ctrl.smartJumpToBottom,
                        child: const Icon(Icons.keyboard_arrow_down),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 弹出长按上下文菜单；复制自包含，其余动作经 dataSource 回调交宿主处理
  void _showContextMenu(BuildContext context, Message message) {
    final text = message.textContent;
    final l10n = context.l10n;
    showMessageContextMenu(
      context,
      message,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: text));
        showAppSnackBar(
          context,
          message: l10n.convStyleCopied,
          type: NotificationType.success,
        );
      },
      onQuote: () =>
          dataSource.onMessageAction?.call(message, MessageAction.quote),
      onRetry: () =>
          dataSource.onMessageAction?.call(message, MessageAction.retry),
      onShare: () =>
          dataSource.onMessageAction?.call(message, MessageAction.share),
      onDelete: () async {
        await dataSource.deleteMessage(message.id);
        if (context.mounted) {
          showAppSnackBar(
            context,
            message: l10n.convStyleDeleted,
            type: NotificationType.success,
          );
        }
      },
    );
  }

  /// 构建单条消息卡片
  ///
  /// [prevSameRole] 为 true 时收紧垂直间距（同角色连续堆叠）；
  /// [layer] 为同角色连续层数，层数越大阴影略增，营造堆叠感。
  Widget _buildMessageCard(
    BuildContext context,
    Message message,
    List<Message> allMessages, {
    required bool prevSameRole,
    required int layer,
  }) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    // 用户蓝色边框，助手绿色边框
    final accentColor = isUser ? Colors.blue : Colors.green;
    // 同角色收紧，不同角色拉开
    final vMargin = prevSameRole ? 4.0 : 8.0;
    // 阴影逐层微增：基础 2 + 每层 0.5，封顶 4
    final elevation = (2.0 + layer * 0.5).clamp(2.0, 4.0);

    final card = Container(
      margin: EdgeInsets.symmetric(vertical: vMargin, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: accentColor,
            width: 4,
          ),
        ),
      ),
      child: Card(
        elevation: elevation,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
            topLeft: Radius.circular(4),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片头部：头像 + 角色名 + 时间
            _buildCardHeader(context, message, isUser, theme),
            // 卡片内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildParts(context, message, allMessages),
            ),
          ],
        ),
      ),
    );

    // 长按弹出统一上下文菜单（复制/引用/重新生成/分享/删除）
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showContextMenu(context, message),
      child: card,
    );

    final l10n = context.l10n;
    final timeStr = _formatDateTime(message.timestamp);
    return Semantics(
      container: true,
      label: isUser
          ? l10n.convStyleUserMessageSemantic(timeStr)
          : l10n.convStyleAssistantMessageSemantic(timeStr),
      child: tappable,
    );
  }

  /// 卡片头部 —— 头像 + 角色名 + 时间戳
  Widget _buildCardHeader(
      BuildContext context, Message message, bool isUser, ThemeData theme) {
    final accentColor = isUser ? Colors.blue : Colors.green;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: isUser
                ? l10n.convStyleUserAvatarSemantic
                : l10n.convStyleAssistantAvatarSemantic,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: accentColor.withValues(alpha: 0.15),
              child: Icon(
                isUser ? Icons.person : Icons.smart_toy,
                size: 18,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser
                      ? l10n.convStyleSenderYou
                      : (message.assistantName ?? l10n.convStyleSenderAssistant),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatDateTime(message.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (message.isStreaming)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  /// 构建卡片内的所有 part
  ///
  /// - 用户消息卡片顶部渲染引用回复 QuoteRefWidget
  /// - 连续工具调用用 groupConsecutiveToolCalls 分组为 ToolGroupCard
  /// - 思考部分传入 isStreaming
  /// - 流式中的助手卡片在最后一个 TextPart 后追加 StreamingCursor
  Widget _buildParts(
      BuildContext context, Message message, List<Message> allMessages) {
    final children = <Widget>[];
    final parts = message.parts;
    final isStreaming = message.isStreaming;

    // 用户引用回复：在卡片顶部渲染 QuoteRefWidget
    if (message.referencedMessageId != null) {
      final refMsg = _findMessageById(allMessages, message.referencedMessageId!);
      if (refMsg != null) {
        children.add(QuoteRefWidget(
          senderName: refMsg.role == MessageRole.user
              ? context.l10n.convStyleSenderYou
              : (refMsg.assistantName ?? context.l10n.convStyleSenderAssistant),
          contentPreview: refMsg.textContent,
          timestamp: refMsg.timestamp,
        ));
      }
    }

    // 连续工具调用分组
    final groups = groupConsecutiveToolCalls(parts);
    var groupIdx = 0;
    int? lastTextChildIndex;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];

      // 命中某个工具组：聚合为 ToolGroupCard（卡片内嵌卡片，自带浅色背景）
      if (groupIdx < groups.length &&
          identical(part, groups[groupIdx].toolCalls.first)) {
        final group = groups[groupIdx];
        children.add(ToolGroupCard(
          toolCalls: group.toolCalls,
          uiState: uiState,
          onUIStateChanged: updateUIState,
        ));
        // 跳过组内所有 part
        i += group.toolCalls.length - 1;
        groupIdx++;
        continue;
      }

      switch (part) {
        case TextPart():
          children.add(TextPartRenderer(part: part));
          lastTextChildIndex = children.length - 1;
        case CodePart():
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          // 未被分组覆盖的单个工具调用（兜底）
          children.add(ToolCallPartRenderer(
            part: part,
            expanded: uiState.expandedToolCallIds.contains(part.id),
            onToggleExpand: () => updateUIState(
              uiState.toggleToolCall(part.id),
            ),
          ));
        case ThinkingPart():
          children.add(ThinkingPartRenderer(
            part: part,
            collapsed: uiState.collapsedThinkingIds.contains(part.id),
            onToggleCollapse: () => updateUIState(
              uiState.toggleThinking(part.id),
            ),
            isStreaming: isStreaming,
          ));
        case ApprovalPart():
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          // 图片在卡片内圆角缩略图展示
          children.add(ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ImagePartRenderer(part: part, maxWidth: double.infinity),
          ));
        case FilePart():
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          children.add(ArtifactPartRenderer(part: part));
        case TaskPart():
          children.add(Text('📋 ${part.title}'));
      }
    }

    // 流式中的助手卡片：在最后一个 TextPart 后追加闪烁光标
    if (isStreaming && lastTextChildIndex != null) {
      children.insert(
        lastTextChildIndex + 1,
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: StreamingCursor(),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// 按 ID 在消息列表中查找被引用消息
  Message? _findMessageById(List<Message> all, String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime time) {
    final y = time.year.toString();
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
