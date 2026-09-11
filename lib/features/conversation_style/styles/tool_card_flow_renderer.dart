import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/build_context_l10n.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_state.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/agent_enhanced_widgets.dart';
import '../widgets/message_animations.dart';
import '../widgets/message_context_menu.dart';
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

  /// 智能滚动控制器（懒初始化，随渲染器 onDetach 释放）
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
    return _ToolCardFlowView(
      scrollCtrl: _scrollCtrl!,
      showJump: _showJump,
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

/// 实际视图：内部维护本地 UI 状态，并用 StreamBuilder 响应消息流
class _ToolCardFlowView extends StatefulWidget {
  final SmartScrollController scrollCtrl;
  final ValueNotifier<bool> showJump;
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _ToolCardFlowView({
    required this.scrollCtrl,
    required this.showJump,
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
        // 新消息到达且用户在底部附近时，自动平滑跟随到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctrl = widget.scrollCtrl;
          if (ctrl.hasClients && ctrl.shouldAutoScroll) {
            ctrl.animateTo(
              ctrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        if (messages.isEmpty) {
          return const Center(
            // ignore: hardcoded_ui_string —— 空态暂无 l10n 键，保留原文案
            child: Text('暂无消息'),
          );
        }
        return StreamBuilder<ConversationState>(
          stream: widget.dataSource.stateStream,
          initialData: widget.dataSource.currentState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data ?? ConversationState.idle;
            return Column(
              children: [
                // 流水线进度指示器（LangGraph GenUI PipelineProgress）
                if (state.totalSteps != null && state.totalSteps! > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: PipelineProgress(
                      totalSteps: state.totalSteps!,
                      completedSteps: state.completedSteps ?? 0,
                      currentStepName: state.currentStepName,
                      hasError: state.error != null,
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        controller: widget.scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final w = _buildMessage(context, messages[index], messages, index, state);
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
                          valueListenable: widget.showJump,
                          builder: (context, show, _) => show
                              ? FloatingActionButton.small(
                                  onPressed: widget.scrollCtrl.smartJumpToBottom,
                                  child: const Icon(Icons.keyboard_arrow_down),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 统一包裹：消息容器语义 label（用户/助手+时间）+ 长按弹出统一菜单
  Widget _buildMessage(
      BuildContext context, Message message, List<Message> all, int index, ConversationState state) {
    final body = _buildMessageBody(context, message, all, index, state);
    final timeStr = _formatTime(message.timestamp);
    final l10n = context.l10n;
    final String? label = switch (message.role) {
      MessageRole.user => l10n.convStyleUserMessageSemantic(timeStr),
      MessageRole.assistant => l10n.convStyleAssistantMessageSemantic(timeStr),
      _ => null,
    };
    return Semantics(
      container: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showContextMenu(context, message),
        child: body,
      ),
    );
  }

  Widget _buildMessageBody(
      BuildContext context, Message message, List<Message> all, int index, ConversationState state) {
    // 用户消息：顶部简洁样式
    if (message.role == MessageRole.user) {
      return _UserPromptBlock(
        message: message,
        onQuoteTap: message.referencedMessageId != null ? () {} : null,
      );
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
        state: state,
      );
    }

    // 主分支：时间线穿插渲染各 part
    // 使用 groupConsecutiveToolCalls 将连续工具调用聚合为组
    final children = <Widget>[];
    final parts = message.parts;
    final groups = groupConsecutiveToolCalls(parts);
    // 任务分组
    final taskGroups = _groupConsecutiveTasks(parts);
    var groupIdx = 0;
    var taskGroupIdx = 0;
    final isStreaming = message.isStreaming;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;

      // 检查是否命中某个工具组
      if (groupIdx < groups.length &&
          part == groups[groupIdx].toolCalls.first) {
        final group = groups[groupIdx];
        children.add(_ToolGroupTimelineNode(
          group: group,
          isLast: isLast,
          uiState: _uiState,
          onUIStateChanged: _update,
        ));
        // 跳过组内所有 part
        i += group.toolCalls.length - 1;
        groupIdx++;
        continue;
      }

      // 检查是否命中某个任务组
      if (taskGroupIdx < taskGroups.length &&
          part == taskGroups[taskGroupIdx].first) {
        final taskGroup = taskGroups[taskGroupIdx];
        children.add(_TaskTimelineNode(
          tasks: taskGroup,
          isLast: isLast,
          uiState: _uiState,
          onUIStateChanged: _update,
        ));
        i += taskGroup.length - 1;
        taskGroupIdx++;
        continue;
      }

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
          // 流式光标附加在文本末尾
          if (isStreaming && isLast) {
            children.add(const Padding(
              padding: EdgeInsets.only(left: 36, bottom: 6),
              child: StreamingCursor(),
            ));
          }
        case ThinkingPart():
          children.add(_ThinkingTimelineNode(
            part: part,
            isLast: isLast,
            collapsed: _uiState.collapsedThinkingIds.contains(part.id),
            onToggle: () => _update(_uiState.toggleThinking(part.id)),
            isStreaming: isStreaming,
          ));
        case ApprovalPart():
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ApprovalPartRenderer(
              part: part,
              onApprove: () => widget.dataSource.approveAction(part.id),
              onReject: () => widget.dataSource.rejectAction(part.id),
              onAllowSession: () => widget.dataSource.approveAction(part.id),
            ),
          ));
        case TaskPart():
          // 单个任务（未被分组的）
          children.add(_TaskTimelineNode(
            tasks: [part],
            isLast: isLast,
            uiState: _uiState,
            onUIStateChanged: _update,
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

    // 追问建议芯片（Perplexity Follow-up 模式）
    if (!isStreaming && state.followUpSuggestions.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(left: 36, top: 8),
        child: FollowUpChips(suggestions: state.followUpSuggestions),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  /// 将连续的 TaskPart 分组
  List<List<TaskPart>> _groupConsecutiveTasks(List<MessagePart> parts) {
    final groups = <List<TaskPart>>[];
    List<TaskPart>? currentGroup;
    for (final part in parts) {
      if (part is TaskPart) {
        currentGroup ??= [];
        currentGroup.add(part);
      } else {
        if (currentGroup != null && currentGroup.isNotEmpty) {
          groups.add(List.unmodifiable(currentGroup));
        }
        currentGroup = null;
      }
    }
    if (currentGroup != null && currentGroup.isNotEmpty) {
      groups.add(List.unmodifiable(currentGroup));
    }
    return groups;
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
          widget.dataSource.onMessageAction?.call(message, MessageAction.quote),
      onRetry: () =>
          widget.dataSource.onMessageAction?.call(message, MessageAction.retry),
      onShare: () =>
          widget.dataSource.onMessageAction?.call(message, MessageAction.share),
      onDelete: () async {
        await widget.dataSource.deleteMessage(message.id);
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

  /// 格式化时间戳（语义 label 用）
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 扩展方法：`List<MessagePart>` 安全判断是否包含某类型
extension _PartTypeCheck on List<MessagePart> {
  bool anyType<T extends MessagePart>() => whereType<T>().isNotEmpty;
}

/// 用户提问块（简洁样式）
class _UserPromptBlock extends StatelessWidget {
  final Message message;
  final VoidCallback? onQuoteTap;
  const _UserPromptBlock({required this.message, this.onQuoteTap});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 引用回复
          if (message.referencedMessageId != null)
            QuoteRefWidget(
              senderName: message.assistantName ?? context.l10n.convStyleSenderAssistant,
              contentPreview: message.textContent,
              timestamp: message.timestamp,
              onTap: onQuoteTap,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // ignore: hardcoded_ui_string —— 空消息占位暂无 l10n 键，保留原文案
                  message.textContent.isEmpty ? '(空)' : message.textContent,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
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

/// 时间线节点：工具调用分组（连续工具聚合）
class _ToolGroupTimelineNode extends StatelessWidget {
  final ToolGroupInfo group;
  final bool isLast;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _ToolGroupTimelineNode({
    required this.group,
    required this.isLast,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = group.hasError;

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
          // 右侧分组卡片
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
              child: ToolGroupCard(
                toolCalls: group.toolCalls,
                uiState: uiState,
                onUIStateChanged: onUIStateChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(ThemeData theme) {
    if (group.hasRunning) {
      return const _PulsingDot(color: Colors.blue, size: 16);
    }
    if (group.hasError) {
      return _StatusDot(color: theme.colorScheme.error, filled: true, size: 16);
    }
    return const _StatusDot(color: Colors.green, filled: true, size: 16);
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
    final showProgress = part.status == ToolCallStatus.running && part.progress != null;

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
                  color: part.isStalled
                      ? Colors.orange
                      : (isError ? theme.colorScheme.error : theme.colorScheme.outlineVariant),
                  width: part.isStalled || isError ? 1.5 : 1,
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
                  // 执行进度条（Claude Code 风格）
                  if (showProgress)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: ToolProgressBar(progress: part.progress!),
                    ),
                  // 停滞警告（Cursor 教训）
                  if (part.isStalled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: StalledToolWarning(
                        stalledSeconds: 30,
                        onCancel: onRetry,
                      ),
                    ),
                  if (expanded) _buildBody(context),
                  if (isError) _buildErrorActions(context),
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
            // 信心徽章（Devin 风格交通灯）
            if (part.confidence != null) ...[
              ConfidenceBadge(level: part.confidence!),
              const SizedBox(width: 8),
            ],
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

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 参数（可折叠 JSON）
          Text(context.l10n.chatMessageWidgetArguments,
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
            // ignore: hardcoded_ui_string —— 工具结果摘要标签暂无 l10n 键，保留原文案
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

  Widget _buildErrorActions(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 错误恢复建议（Claude Code 风格：可操作建议 + 一键重试）
          if (part.recoverySuggestions != null &&
              part.recoverySuggestions!.isNotEmpty)
            ErrorRecoverySuggestions(
              suggestions: part.recoverySuggestions!,
              onRetry: onRetry,
            ),
          if (part.recoverySuggestions == null ||
              part.recoverySuggestions!.isEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(context.l10n.commonRetry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {}, // 跳过：由上层切换到下一个步骤
                  icon: const Icon(Icons.skip_next, size: 16),
                  // ignore: hardcoded_ui_string —— 跳过按钮暂无 l10n 键，保留原文案
                  label: const Text('跳过'),
                ),
              ],
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
  final bool isStreaming;

  const _ThinkingTimelineNode({
    required this.part,
    required this.isLast,
    required this.collapsed,
    required this.onToggle,
    this.isStreaming = false,
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
              // 流式中用脉冲点，完成后用静态点
              if (isStreaming)
                const _PulsingDot(color: Colors.purple, size: 14)
              else
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
                isStreaming: isStreaming,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间线节点：任务列表（Windsurf Todo List 模式）
class _TaskTimelineNode extends StatelessWidget {
  final List<TaskPart> tasks;
  final bool isLast;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _TaskTimelineNode({
    required this.tasks,
    required this.isLast,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInProgress = tasks.any((t) => t.isInProgress);
    final allCompleted = tasks.every((t) => t.isCompleted);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧 rail：状态点 + 连接线
          SizedBox(
            width: 28,
            child: Column(
              children: [
                hasInProgress
                    ? const _PulsingDot(color: Colors.blue, size: 16)
                    : _StatusDot(
                        color: allCompleted ? Colors.green : theme.colorScheme.primary,
                        filled: allCompleted,
                        size: 16,
                      ),
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Container(width: 2, color: theme.colorScheme.outlineVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧任务列表卡片
          Expanded(
            child: TaskListRenderer(
              tasks: tasks,
              interactive: true,
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
  final ConversationState state;

  const _SimpleAssistantBlock({
    required this.message,
    required this.uiState,
    required this.onUIStateChanged,
    this.state = ConversationState.idle,
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
        children: [
          ...message.parts
              .map((p) => MessagePartRenderer(
                    part: p,
                    uiState: uiState,
                    onUIStateChanged: onUIStateChanged,
                  )),
          // 追问建议芯片
          if (!message.isStreaming && state.followUpSuggestions.isNotEmpty)
            FollowUpChips(suggestions: state.followUpSuggestions),
        ],
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
