import 'package:flutter/material.dart';

import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 09：多助手协作（MultiAssistant）
///
/// 不同助手用颜色编码 + 名称标签区分：
///   蓝=研究员 / 黄=编码员 / 红=评审员 / 绿=执行者 / 紫=协调员 / 灰=通用助手。
/// 每条消息显示助手头像（颜色圆 + 首字母）、名称、角色标签；
/// 任务交接时用 AnimatedSwitcher + 箭头动画指示。
class MultiAssistantRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.multiAssistant;

  @override
  Widget build(BuildContext context) {
    return _MultiAssistantView(
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

/// 颜色标识 -> 实际颜色
Color _resolveColor(String? colorKey) {
  switch (colorKey) {
    case 'blue':
      return Colors.blue;
    case 'yellow':
      return Colors.amber;
    case 'red':
      return Colors.red;
    case 'green':
      return Colors.green;
    case 'purple':
      return Colors.purple;
    default:
      return Colors.grey;
  }
}

/// 颜色标识 -> 角色名
String _resolveRole(String? colorKey) {
  switch (colorKey) {
    case 'blue':
      return '研究员';
    case 'yellow':
      return '编码员';
    case 'red':
      return '评审员';
    case 'green':
      return '执行者';
    case 'purple':
      return '协调员';
    default:
      return '通用助手';
  }
}

class _MultiAssistantView extends StatefulWidget {
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _MultiAssistantView({
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_MultiAssistantView> createState() => _MultiAssistantViewState();
}

class _MultiAssistantViewState extends State<_MultiAssistantView> {
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
        if (messages.isEmpty) return const Center(child: Text('暂无消息'));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final prev = index > 0 ? messages[index - 1] : null;
            return _buildMessage(context, messages[index], prev);
          },
        );
      },
    );
  }

  Widget _buildMessage(BuildContext context, Message message, Message? prev) {
    // 用户消息：右侧 + 用户头像
    if (message.role == MessageRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: message.parts
                .map((p) => MessagePartRenderer(
                      part: p,
                      uiState: _uiState,
                      onUIStateChanged: _update,
                    ))
                .toList(),
          ),
        ),
      );
    }
    if (message.role == MessageRole.system) {
      return _SystemDivider(text: message.textContent);
    }

    // 助手消息：检测交接（assistantId 变化）
    final isHandoff = prev != null &&
        prev.role == MessageRole.assistant &&
        (prev.assistantId ?? '') != (message.assistantId ?? '');

    final color = _resolveColor(message.assistantColor);
    final name = message.assistantName ?? _resolveRole(message.assistantColor);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isHandoff)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _HandoffIndicator(
              from: prev.assistantName ?? _resolveRole(prev.assistantColor),
              to: name,
              key: ValueKey('handoff_${prev.id}_${message.id}'),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 助手头像：颜色圆 + 首字母
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: color, width: 4)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 3,
                        offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称 + 角色标签（用对应颜色背景）
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _resolveRole(message.assistantColor),
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...message.parts
                        .map((p) => MessagePartRenderer(
                              part: p,
                              uiState: _uiState,
                              onUIStateChanged: _update,
                            )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 任务交接动画指示器
class _HandoffIndicator extends StatelessWidget {
  final String from;
  final String to;
  const _HandoffIndicator({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(from,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward,
              size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(to,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

class _SystemDivider extends StatelessWidget {
  final String text;
  const _SystemDivider({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(text,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }
}
