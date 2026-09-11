import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 06：工具卡片流（ToolCardFlow）
///
/// 每个工具调用是独立卡片，纵向时间线布局。
/// 左侧垂直连接线 + 状态点（已完成=绿、进行中=蓝闪烁、待执行=灰空心）。
/// 失败时红色边框 + 重试/跳过按钮；文本回答在工具流之间穿插显示。
/// 若消息中没有任何工具调用，退化为简洁列表显示。
class ToolCardFlowRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.toolCardFlow;

  @override
  Widget build(BuildContext context) {
    return _ToolCardFlowView(
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

/// 实际视图：内部维护本地 UI 状态，并用 StreamBuilder 响应消息流
class _ToolCardFlowView extends StatefulWidget {
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _ToolCardFlowView({
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_ToolCardFlowView> createState() => _ToolCardFlowViewState();
}

class _ToolCardFlowViewState extends State<_ToolCardFlowView> {
  late ConversationUIState _uiState;

  @override
  void initState() {
    super.initState();
    _uiState = widget.initialUiState;
  }

  void _update(ConversationUIState s) {
    setState(() => _uiState = s);
    widget.onUIStateChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: widget.dataSource.messageStream,
      initialData: widget.dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        if (messages.isEmpty) {
          return const Center(child: Text('暂无消息'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index], messages, index),
        );
      },
    );
  }

  Widget _buildMessage(
      BuildContext context, Message message, List<Message> all, int index) {
    // 用户消息：顶部简洁样式
    if (message.role == MessageRole.user) {
      return _UserPromptBlock(message: message);
    }
    // 系统消息
    if (message.role == MessageRole.system) {
      return _SystemBlock(text: message.textContent);
    }

    final hasTool = message.parts.anyType<ToolCallPart>();
    // 退化分支：无工具调用时用简洁列表
    if (!hasTool) {
      return _SimpleAssistantBlock(
        message: message,
        uiState: _uiState,
        onUIStateChanged: _update,
      );
    }

    // 主分支：时间线穿插渲染各 part
    final children = <Widget>[];
    final parts = message.parts;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      switch (part) {
        case ToolCallPart():
          children.add(_ToolTimelineNode(
            part: part,
            isLast: isLast,
            expanded: _uiState.expandedToolCallIds.contains(part.id),
            onToggle: () => _update(_uiState.toggleToolCall(part.id)),
            onRetry: () => widget.dataSource.retryMessage(message.id),
          ));
        case TextPart():
          // 文本回答穿插在工具流之间，用不同背景区分
          children.add(_InterleavedTextBlock(part: part));
        case ThinkingPart():
          children.add(_ThinkingTimelineNode(
            part: part,
            isLast: isLast,
            collapsed: _uiState.collapsedThinkingIds.contains(part.id),
            onToggle: () => _update(_uiState.toggleThinking(part.id)),
          ));
        case ApprovalPart():
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ApprovalPartRenderer(
              part: part,
              onApprove: () => widget.dataSource.approveAction(part.id),
              onReject: () => widget.dataSource.rejectAction(part.id),
            ),
          ));
        default:
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MessagePartRenderer(
              part: part,
              uiState: _uiState,
              onUIStateChanged: _update,
            ),
          ));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// 扩展方法：`List<MessagePart>` 安全判断是否包含某类型
extension _PartTypeCheck on List<MessagePart> {
  bool anyType<T extends MessagePart>() => whereType<T>().isNotEmpty;
}

/// 用户提问块（简洁样式）
class _UserPromptBlock extends StatelessWidget {
  final Message message;
  const _UserPromptBlock({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.textContent.isEmpty ? '(空)' : message.textContent,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// 系统消息块
class _SystemBlock extends StatelessWidget {
  final String text;
  const _SystemBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic))),
        ],
      ),
    );
  }
}

/// 穿插在工具流之间的文本回答（不同背景区分）
class _InterleavedTextBlock extends StatelessWidget {
  final TextPart part;
  const _InterleavedTextBlock({required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 36, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.tertiary, width: 3),
        ),
      ),
      child: TextPartRenderer(part: part),
    );
  }
}

/// 时间线节点：工具调用卡片
class _ToolTimelineNode extends StatelessWidget {
  final ToolCallPart part;
  final bool isLast;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRetry;

  const _ToolTimelineNode({
    required this.part,
    required this.isLast,
    required this.expanded,
    required this.onToggle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = part.status == ToolCallStatus.error;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧 rail：状态点 + 连接线
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _buildDot(theme),
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Container(width: 2, color: theme.colorScheme.outlineVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧卡片
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isError ? theme.colorScheme.error : theme.colorScheme.outlineVariant,
                  width: isError ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme),
                  if (expanded) _buildBody(theme),
                  if (isError) _buildErrorActions(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(ThemeData theme) {
    switch (part.status) {
      case ToolCallStatus.running:
        // 进行中：蓝色闪烁圆点
        return const _PulsingDot(color: Colors.blue, size: 16);
      case ToolCallStatus.success:
        return const _StatusDot(color: Colors.green, filled: true, size: 16);
      case ToolCallStatus.error:
        return _StatusDot(color: theme.colorScheme.error, filled: true, size: 16);
      case ToolCallStatus.pending:
        // 待执行：灰色空心圆
        return const _StatusDot(color: Colors.grey, filled: false, size: 16);
      case ToolCallStatus.cancelled:
        return const _StatusDot(color: Colors.grey, filled: false, size: 16);
    }
  }

  Widget _buildHeader(ThemeData theme) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                part.toolName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (part.duration != null)
              Text(
                '${part.duration!.inMilliseconds} ms',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 参数（可折叠 JSON）
          Text('参数',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              const JsonEncoder.withIndent('  ').convert(part.arguments),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          // 结果摘要
          if (part.result != null) ...[
            const SizedBox(height: 10),
            Text('结果摘要',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              part.result.toString(),
              style: theme.textTheme.bodySmall,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (part.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(part.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () {}, // 跳过：由上层切换到下一个步骤
            icon: const Icon(Icons.skip_next, size: 16),
            label: const Text('跳过'),
          ),
        ],
      ),
    );
  }
}

/// 时间线节点：思考过程
class _ThinkingTimelineNode extends StatelessWidget {
  final ThinkingPart part;
  final bool isLast;
  final bool collapsed;
  final VoidCallback onToggle;

  const _ThinkingTimelineNode({
    required this.part,
    required this.isLast,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(children: [
              const _StatusDot(color: Colors.purple, filled: true, size: 14),
              Expanded(
                child: isLast
                    ? const SizedBox.shrink()
                    : Container(width: 2, color: theme.colorScheme.outlineVariant),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: ThinkingPartRenderer(
                part: part,
                collapsed: collapsed,
                onToggleCollapse: onToggle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 退化模式：无工具调用时的简洁助手块
class _SimpleAssistantBlock extends StatelessWidget {
  final Message message;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _SimpleAssistantBlock({
    required this.message,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: message.parts
            .map((p) => MessagePartRenderer(
                  part: p,
                  uiState: uiState,
                  onUIStateChanged: onUIStateChanged,
                ))
            .toList(),
      ),
    );
  }
}

/// 静态状态点（已完成/待执行）
class _StatusDot extends StatelessWidget {
  final Color color;
  final bool filled;
  final double size;
  const _StatusDot({required this.color, required this.filled, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

/// 闪烁状态点（进行中）
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, required this.size});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: widget.color
                .withValues(alpha: 0.4 + 0.6 * _controller.value),
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2),
          ),
        );
      },
    );
  }
}
