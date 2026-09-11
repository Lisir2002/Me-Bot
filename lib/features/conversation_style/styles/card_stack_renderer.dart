import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 04: 卡片堆叠式渲染器
///
/// 布局特点：
/// - 每条消息是一个带阴影的 Card 组件，视觉层次分明
/// - 卡片头部（Card header）显示头像 + 角色名 + 时间
/// - 用户消息卡片左侧蓝色边框标记
/// - 助手消息卡片左侧绿色边框标记
/// - 卡片间距 8px，带 elevation 阴影
/// - 图片在卡片内全宽显示
///
/// 适用场景：文件分享、图片密集、视觉驱动
class CardStackRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.cardStack;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessageCard(context, messages[index]),
        );
      },
    );
  }

  /// 构建单条消息卡片
  Widget _buildMessageCard(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    // 用户蓝色边框，助手绿色边框
    final accentColor = isUser ? Colors.blue : Colors.green;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
        elevation: 2,
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
              child: _buildParts(context, message),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片头部 —— 头像 + 角色名 + 时间戳
  Widget _buildCardHeader(
      BuildContext context, Message message, bool isUser, ThemeData theme) {
    final accentColor = isUser ? Colors.blue : Colors.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            child: Icon(
              isUser ? Icons.person : Icons.smart_toy,
              size: 18,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser ? '用户' : (message.assistantName ?? '助手'),
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
  Widget _buildParts(BuildContext context, Message message) {
    final children = <Widget>[];

    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          children.add(TextPartRenderer(part: part));
        case CodePart():
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          // 卡片内嵌工具调用渲染器
          final isExpanded =
              uiState.expandedToolCallIds.contains(part.id);
          children.add(ToolCallPartRenderer(
            part: part,
            expanded: isExpanded,
            onToggleExpand: () => updateUIState(
              uiState.toggleToolCall(part.id),
            ),
          ));
        case ThinkingPart():
          final isCollapsed =
              uiState.collapsedThinkingIds.contains(part.id);
          children.add(ThinkingPartRenderer(
            part: part,
            collapsed: isCollapsed,
            onToggleCollapse: () => updateUIState(
              uiState.toggleThinking(part.id),
            ),
          ));
        case ApprovalPart():
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          // 图片全宽显示
          children.add(ImagePartRenderer(part: part, maxWidth: double.infinity));
        case FilePart():
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          children.add(ArtifactPartRenderer(part: part));
      }
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
