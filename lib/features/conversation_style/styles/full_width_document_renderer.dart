// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 02: 全宽文档式渲染器
///
/// 布局特点：
/// - 消息占满宽度，无气泡边框，用 Divider 分隔线区分消息
/// - 不显示头像，用角色标签（"用户"/"助手"）代替
/// - 不显示时间戳
/// - 工具调用用可展开的 ExpansionTile 折叠引用
/// - 文本使用 1.8 行高，适合长文本阅读
/// - 用户消息用引用块样式（左边框 + 斜体）区分
///
/// 适用场景：长文本、代码密集、文档生成
class FullWidthDocumentRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.fullWidthDocument;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: messages.length,
          separatorBuilder: (context, index) => const Divider(height: 32),
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  /// 构建单条消息 —— 全宽布局，角色标签 + 内容
  Widget _buildMessage(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 角色标签行
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isUser ? '用户' : '助手',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isUser
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (message.modelId != null) ...[
              const SizedBox(width: 8),
              Text(
                message.modelId!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // 消息内容
        _buildParts(context, message, isUser),
      ],
    );
  }

  /// 构建消息内部的所有 part
  Widget _buildParts(BuildContext context, Message message, bool isUser) {
    final children = <Widget>[];

    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          // 用户消息用引用块样式，助手消息用大行距正文
          if (isUser) {
            children.add(_buildQuoteText(context, part));
          } else {
            children.add(TextPartRenderer(
              part: part,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.8,
                  ),
            ));
          }
        case CodePart():
          // 代码块显示运行按钮
          children.add(CodePartRenderer(
            part: part,
            showRunButton: true,
          ));
        case ToolCallPart():
          // 工具调用用 ExpansionTile 折叠引用
          children.add(_buildToolCallExpansion(context, part));
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

  /// 用户消息引用块样式 —— 左边框 + 斜体
  Widget _buildQuoteText(BuildContext context, TextPart part) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: SelectionArea(
        child: Text(
          part.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.8,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 工具调用折叠引用 —— 用 ExpansionTile 包裹
  Widget _buildToolCallExpansion(
      BuildContext context, ToolCallPart part) {
    final theme = Theme.of(context);
    final isExpanded = uiState.expandedToolCallIds.contains(part.id);

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (part.status) {
      case ToolCallStatus.pending:
        statusColor = theme.colorScheme.onSurfaceVariant;
        statusIcon = Icons.hourglass_empty;
        statusLabel = '等待中';
      case ToolCallStatus.running:
        statusColor = Colors.blue;
        statusIcon = Icons.autorenew;
        statusLabel = '执行中';
      case ToolCallStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusLabel = '成功';
      case ToolCallStatus.error:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.error;
        statusLabel = '失败';
      case ToolCallStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        statusLabel = '已取消';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                updateUIState(uiState.toggleToolCall(part.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          part.toolName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$statusLabel'
                          '${part.duration != null ? ' · ${part.duration!.inMilliseconds}ms' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 参数
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '参数',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      part.arguments.isEmpty
                          ? '{}'
                          : part.arguments.entries
                              .map((e) => '  "${e.key}": ${e.value}')
                              .join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  // 结果
                  if (part.result != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '结果',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        part.result.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  // 错误信息
                  if (part.status == ToolCallStatus.error &&
                      part.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        part.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
