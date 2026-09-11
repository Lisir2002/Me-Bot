import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 01: 经典气泡式渲染器
///
/// 布局特点：
/// - 用户消息右对齐，助手消息左对齐，圆角气泡
/// - 头像显示（用户 Icons.person，助手 Icons.smart_toy）
/// - 时间戳显示在气泡下方，小字
/// - 工具调用以内联 chip 样式展示
/// - 正在生成的消息显示打字光标动画
/// - 气泡最大宽度不超过屏幕宽度的 75%
///
/// 适用场景：日常聊天、短对话、通用场景
class ClassicBubbleRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.classicBubble;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  /// 构建单条消息行（头像 + 气泡 + 时间戳）
  Widget _buildMessage(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.75;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 助手头像在左侧
          if (!isUser) _buildAvatar(context, isUser),
          if (!isUser) const SizedBox(width: 8),
          // 气泡主体（受限最大宽度）
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 气泡内容
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isUser
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                      bottomRight: isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                    ),
                  ),
                  child: _buildParts(context, message, isUser),
                ),
                const SizedBox(height: 4),
                // 时间戳（气泡下方小字）
                Text(
                  _formatTime(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // 用户头像在右侧
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildAvatar(context, isUser),
        ],
      ),
    );
  }

  /// 构建头像
  Widget _buildAvatar(BuildContext context, bool isUser) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.secondaryContainer,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 18,
        color: isUser
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSecondaryContainer,
      ),
    );
  }

  /// 构建消息内部的所有 part
  Widget _buildParts(BuildContext context, Message message, bool isUser) {
    final children = <Widget>[];

    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          // 文本部分 + 流式打字光标
          children.add(_buildTextPart(context, part, message.isStreaming));
        case CodePart():
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          // 工具调用内联 chip 样式
          children.add(_buildToolChip(context, part));
        case ThinkingPart():
          // 思考过程默认折叠
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
            onApprove: () =>
                dataSource.approveAction(part.id),
            onReject: () =>
                dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          children.add(ImagePartRenderer(part: part));
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

  /// 构建文本部分（含流式打字光标）
  Widget _buildTextPart(
      BuildContext context, TextPart part, bool isStreaming) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectionArea(
          child: Text(
            part.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.4,
            ),
          ),
        ),
        // 流式输出时显示打字光标
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: _BlinkingCursor(),
          ),
      ],
    );
  }

  /// 构建工具调用内联 chip
  Widget _buildToolChip(BuildContext context, ToolCallPart part) {
    final theme = Theme.of(context);
    Color statusColor;
    IconData statusIcon;
    switch (part.status) {
      case ToolCallStatus.pending:
        statusColor = theme.colorScheme.onSurfaceVariant;
        statusIcon = Icons.hourglass_empty;
      case ToolCallStatus.running:
        statusColor = Colors.blue;
        statusIcon = Icons.autorenew;
      case ToolCallStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      case ToolCallStatus.error:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.error;
      case ToolCallStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 6),
          Text(
            part.toolName,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
          if (part.duration != null) ...[
            const SizedBox(width: 6),
            Text(
              '${part.duration!.inMilliseconds}ms',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 格式化时间戳
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 打字光标动画 —— 流式输出时闪烁的竖线
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value > 0.5 ? 1.0 : 0.0,
          child: Container(
            width: 2,
            height: 16,
            color: theme.colorScheme.primary,
          ),
        );
      },
    );
  }
}
