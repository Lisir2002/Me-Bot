import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 03: 极简流式渲染器
///
/// 布局特点：
/// - 纯文本流，无气泡无边框无头像
/// - 不显示时间戳
/// - 工具调用只显示极简状态行（"🔧 正在调用 web_search..."）
/// - 代码块用等宽字体，无装饰（简单 Container + 背景色）
/// - 思考过程完全不显示
/// - 用户消息用 ">" 前缀标记，灰色
/// - 助手消息正常文本
///
/// 适用场景：快速问答、实时流式输出、专注阅读
/// 信息密度最低，追求最快的流式渲染性能
class MinimalStreamRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.minimalStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  /// 构建单条消息 —— 极简纯文本流
  Widget _buildMessage(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _buildParts(context, message, isUser, theme),
      ),
    );
  }

  /// 构建消息内部的所有 part（极简模式）
  List<Widget> _buildParts(
      BuildContext context, Message message, bool isUser, ThemeData theme) {
    final children = <Widget>[];

    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          // 用户消息用 ">" 前缀灰色，助手正常文本
          children.add(TextPartRenderer(
            part: part,
            style: isUser
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ));
          // 用户消息添加 ">" 前缀标记（通过前置文本）
          if (isUser) {
            // 在 TextPartRenderer 外面包一层 Row 加 "> " 前缀
            children.removeLast();
            children.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '> ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: TextPartRenderer(
                    part: part,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ));
          }
        case CodePart():
          // 极简代码块：等宽字体 + 简单背景
          children.add(_buildMinimalCode(context, part, theme));
        case ToolCallPart():
          // 极简工具调用：只显示状态行
          children.add(_buildMinimalToolStatus(context, part, theme));
        case ThinkingPart():
          // 极简模式完全不显示思考过程
          break;
        case ApprovalPart():
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          children.add(ImagePartRenderer(part: part));
        case FilePart():
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          children.add(ArtifactPartRenderer(part: part));
      }
    }

    return children;
  }

  /// 极简代码块 —— 无装饰，仅背景色 + 等宽字体
  Widget _buildMinimalCode(
      BuildContext context, CodePart part, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            part.language,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            part.code,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// 极简工具调用状态行 —— "🔧 正在调用 web_search..."
  Widget _buildMinimalToolStatus(
      BuildContext context, ToolCallPart part, ThemeData theme) {
    String statusEmoji;
    String statusText;
    switch (part.status) {
      case ToolCallStatus.pending:
        statusEmoji = '⏳';
        statusText = '等待调用 ${part.toolName}';
      case ToolCallStatus.running:
        statusEmoji = '🔧';
        statusText = '正在调用 ${part.toolName}';
      case ToolCallStatus.success:
        statusEmoji = '✅';
        statusText = '${part.toolName} 完成';
      case ToolCallStatus.error:
        statusEmoji = '❌';
        statusText = '${part.toolName} 失败';
      case ToolCallStatus.cancelled:
        statusEmoji = '🚫';
        statusText = '${part.toolName} 已取消';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$statusEmoji $statusText',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}
