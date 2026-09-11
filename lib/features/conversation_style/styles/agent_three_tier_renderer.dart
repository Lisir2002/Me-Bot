// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/conversation_state.dart';
import '../models/message_part.dart';
import '../widgets/agent_enhanced_widgets.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 05: Agent 三层级渲染器（⭐ 重点样式）
///
/// 布局特点 —— 三级视觉层级：
/// - **Primary（一级）**：用户消息 + 助手最终回答 —— 全宽醒目，大字体，无缩进，白色背景
/// - **Secondary（二级）**：子助手结果 —— 紧凑弱化，左边缩进 24px，浅灰背景，小字体
/// - **Tertiary（三级）**：工具调用/思考 —— 内联 chip，左边缩进 48px，最小字体，默认折叠
///
/// 附加功能：
/// - 工具调用可折叠分组，显示工具名/参数/耗时/结果摘要
/// - 思考过程可展开块，显示 token 消耗
/// - 人工确认（ApprovalPart）显示高风险操作确认卡片
/// - 流式输出时正在生成的一级消息显示进度条
///
/// 适用场景：Agent 多工具调用、复杂任务、深度推理
/// 信息密度高但可折叠，复杂 Agent 任务首选
class AgentThreeTierRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.agentThreeTier;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, messageSnapshot) {
        final messages = messageSnapshot.data ?? [];
        return StreamBuilder<ConversationState>(
          stream: dataSource.stateStream,
          initialData: dataSource.currentState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data ?? ConversationState.idle;
            return Column(
              children: [
                // 任务模式切换栏（Cline Plan/Act 双模式）
                if (state.taskMode != TaskExecutionMode.auto ||
                    state.totalSteps != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        TaskModeSwitcher(
                          currentMode: state.taskMode,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                // 流水线进度指示器（LangGraph GenUI PipelineProgress）
                if (state.totalSteps != null && state.totalSteps! > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: PipelineProgress(
                      totalSteps: state.totalSteps!,
                      completedSteps: state.completedSteps ?? 0,
                      currentStepName: state.currentStepName,
                      hasError: state.error != null,
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessage(context, messages[index], state),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 根据消息内容判断视觉层级
  ///
  /// - Primary: 用户消息、有实质文本的助手消息
  /// - Secondary: 工具结果消息、子助手中间结果
  /// - Tertiary: 纯工具调用/思考（无文本）
  _Tier _classifyTier(Message message) {
    if (message.role == MessageRole.user) return _Tier.primary;
    if (message.role == MessageRole.tool) return _Tier.secondary;

    // 助手消息：判断是否有实质文本内容
    final hasText = message.textContent.trim().isNotEmpty;
    final hasSubAssistant = message.assistantId != null;

    if (hasText) return _Tier.primary;
    if (hasSubAssistant) return _Tier.secondary;
    return _Tier.tertiary;
  }

  /// 构建单条消息（按层级渲染）
  Widget _buildMessage(
      BuildContext context, Message message, ConversationState state) {
    final tier = _classifyTier(message);
    final isGeneratingThis =
        state.generatingMessageId != null &&
            state.generatingMessageId == message.id;

    switch (tier) {
      case _Tier.primary:
        return _buildPrimaryTier(context, message, isGeneratingThis, state);
      case _Tier.secondary:
        return _buildSecondaryTier(context, message);
      case _Tier.tertiary:
        return _buildTertiaryTier(context, message);
    }
  }

  // ==========================================================================
  // Primary（一级）—— 用户消息 + 助手最终回答
  // 无缩进，白色背景，正常字体，全宽醒目
  // ==========================================================================
  Widget _buildPrimaryTier(BuildContext context, Message message,
      bool isGenerating, ConversationState state) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 角色标签行
          Row(
            children: [
              Icon(
                isUser ? Icons.person : Icons.auto_awesome,
                size: 16,
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? '用户' : (message.assistantName ?? '助手'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isUser
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary,
                ),
              ),
              const Spacer(),
              if (message.totalTokens != null)
                Text(
                  '${message.totalTokens} tokens',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 一级消息正文（大字体）
          ..._buildPrimaryParts(context, message, isGenerating && state.isGenerating, state),
          // 流式生成进度条
          if (isGenerating && state.isGenerating)
            _buildProgressIndicator(context, state),
          // 追问建议芯片（Perplexity Follow-up 模式）
          if (!isGenerating && state.followUpSuggestions.isNotEmpty)
            FollowUpChips(suggestions: state.followUpSuggestions),
        ],
      ),
    );
  }

  /// 一级消息的 parts —— 文本用大字体，工具调用/思考降级为三级内联
  /// 连续 TaskPart 聚合为 TaskListRenderer（Windsurf Todo List 模式）
  List<Widget> _buildPrimaryParts(
      BuildContext context, Message message, bool isStreaming, ConversationState state) {
    final children = <Widget>[];

    // 用户引用回复
    if (message.role == MessageRole.user &&
        message.referencedMessageId != null) {
      children.add(QuoteRefWidget(
        senderName: message.assistantName ?? '助手',
        contentPreview: message.textContent,
        timestamp: message.timestamp,
      ));
    }

    // 扫描 parts，将连续 ToolCallPart 分组为 ToolGroupCard
    final groups = groupConsecutiveToolCalls(message.parts);
    // 扫描 parts，将连续 TaskPart 分组为 TaskListRenderer
    final taskGroups = _groupConsecutiveTasks(message.parts);
    var groupIdx = 0;
    var taskGroupIdx = 0;

    for (var i = 0; i < message.parts.length; i++) {
      // 检查是否命中某个工具组
      if (groupIdx < groups.length &&
          i == message.parts.indexOf(groups[groupIdx].toolCalls.first)) {
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

      // 检查是否命中某个任务组
      if (taskGroupIdx < taskGroups.length &&
          i == message.parts.indexOf(taskGroups[taskGroupIdx].first)) {
        final taskGroup = taskGroups[taskGroupIdx];
        children.add(TaskListRenderer(
          tasks: taskGroup,
          interactive: true,
          onStatusChanged: (task, newStatus) {
            // 任务状态切换：更新数据源中的任务状态
            // 实际项目中通过 dataSource 更新，此处为 UI 交互占位
          },
        ));
        i += taskGroup.length - 1;
        taskGroupIdx++;
        continue;
      }

      final part = message.parts[i];
      switch (part) {
        case TextPart():
          children.add(TextPartRenderer(
            part: part,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                ),
          ));
        case CodePart():
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          // 单个工具调用（未被分组覆盖的）也降级为三级 chip
          children.add(_buildTertiaryToolChip(context, part));
        case ThinkingPart():
          // 思考过程使用增强渲染器，传入流式状态
          children.add(ThinkingPartRenderer(
            part: part,
            collapsed: uiState.collapsedThinkingIds.contains(part.id),
            onToggleCollapse: () =>
                updateUIState(uiState.toggleThinking(part.id)),
            isStreaming: isStreaming,
          ));
        case ApprovalPart():
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
            onAllowSession: () => dataSource.approveAction(part.id),
          ));
        case ImagePart():
          children.add(ImagePartRenderer(part: part));
        case FilePart():
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          children.add(ArtifactPartRenderer(part: part));
        case TaskPart():
          // 单个任务（未被分组覆盖的）也渲染为任务列表
          children.add(TaskListRenderer(tasks: [part]));
      }
    }

    // 流式光标
    if (isStreaming) {
      children.add(const StreamingCursor());
    }
    return children;
  }

  /// 将连续的 TaskPart 分组，返回分组列表（不修改原列表）
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

  /// 流式生成进度条
  Widget _buildProgressIndicator(
      BuildContext context, ConversationState state) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: state.generationProgress,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
        if (state.currentPhase != null) ...[
          const SizedBox(height: 4),
          Text(
            state.currentPhase!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // Secondary（二级）—— 子助手结果
  // 左边缩进 24px，浅灰背景，小字体
  // ==========================================================================
  Widget _buildSecondaryTier(BuildContext context, Message message) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 24, right: 12, top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 二级标签
          Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 14,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
              Text(
                message.assistantName ?? '子助手结果',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 二级内容（小字体）
          ..._buildSecondaryParts(context, message),
        ],
      ),
    );
  }

  /// 二级消息的 parts —— 小字体，紧凑布局
  List<Widget> _buildSecondaryParts(BuildContext context, Message message) {
    final children = <Widget>[];
    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          children.add(TextPartRenderer(
            part: part,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ));
        case CodePart():
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          children.add(ToolCallPartRenderer(
            part: part,
            expanded:
                uiState.expandedToolCallIds.contains(part.id),
            onToggleExpand: () => updateUIState(
              uiState.toggleToolCall(part.id),
            ),
          ));
        case ThinkingPart():
          children.add(ThinkingPartRenderer(
            part: part,
            collapsed:
                uiState.collapsedThinkingIds.contains(part.id),
            onToggleCollapse: () => updateUIState(
              uiState.toggleThinking(part.id),
            ),
            isStreaming: message.isStreaming,
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
        case TaskPart():
          children.add(TaskListRenderer(tasks: [part]));
      }
    }
    return children;
  }

  // ==========================================================================
  // Tertiary（三级）—— 工具调用/思考
  // 左边缩进 48px，chip 样式，最小字体，默认折叠
  // ==========================================================================
  Widget _buildTertiaryTier(BuildContext context, Message message) {
    final children = <Widget>[];

    // 扫描 parts，将连续 ToolCallPart 分组为 ToolGroupCard
    final groups = groupConsecutiveToolCalls(message.parts);
    var groupIdx = 0;

    for (var i = 0; i < message.parts.length; i++) {
      // 检查是否命中某个工具组
      if (groupIdx < groups.length &&
          message.parts[i] == groups[groupIdx].toolCalls.first) {
        final group = groups[groupIdx];
        children.add(ToolGroupCard(
          toolCalls: group.toolCalls,
          uiState: uiState,
          onUIStateChanged: updateUIState,
        ));
        i += group.toolCalls.length - 1;
        groupIdx++;
        continue;
      }

      final part = message.parts[i];
      children.add(_buildTertiaryPart(context, part, message.isStreaming));
    }

    return Padding(
      padding: const EdgeInsets.only(left: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildTertiaryPart(BuildContext context, MessagePart part,
      [bool isStreaming = false]) {
    switch (part) {
      case ToolCallPart():
        return _buildTertiaryToolChip(context, part);
      case ThinkingPart():
        return _buildTertiaryThinking(context, part, isStreaming);
      case TextPart():
        // 三级中的文本也用最小字体
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: TextPartRenderer(
            part: part,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        );
      default:
        return MessagePartRenderer(
          part: part,
          uiState: uiState,
          onUIStateChanged: updateUIState,
        );
    }
  }

  /// 三级工具调用 chip —— 紧凑可折叠，显示工具名/参数/耗时/结果摘要
  Widget _buildTertiaryToolChip(
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
        statusLabel = '等待';
      case ToolCallStatus.running:
        statusColor = Colors.blue;
        statusIcon = Icons.autorenew;
        statusLabel = '执行中';
      case ToolCallStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusLabel = '完成';
      case ToolCallStatus.error:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.error;
        statusLabel = '失败';
      case ToolCallStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        statusLabel = '取消';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: part.isStalled
              ? Colors.orange
              : statusColor.withValues(alpha: 0.3),
          width: part.isStalled ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // chip 头部：工具名 + 状态 + 耗时 + 信心徽章
          InkWell(
            onTap: () =>
                updateUIState(uiState.toggleToolCall(part.id)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    part.toolName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: statusColor,
                    ),
                  ),
                  // 信心徽章（Devin 风格交通灯）
                  if (part.confidence != null) ...[
                    const SizedBox(width: 4),
                    ConfidenceBadge(level: part.confidence!),
                  ],
                  if (part.duration != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${part.duration!.inMilliseconds}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // 执行进度条（Claude Code 风格）
          if (part.status == ToolCallStatus.running && part.progress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: ToolProgressBar(progress: part.progress!),
            ),
          // 停滞警告（Cursor 教训）
          if (part.isStalled)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: StalledToolWarning(stalledSeconds: 30),
            ),
          // 展开内容：参数 + 结果摘要
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (part.arguments.isNotEmpty)
                    Text(
                      _formatArgs(part.arguments),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (part.result != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '→ ${part.result.toString().length > 80 ? '${part.result.toString().substring(0, 80)}...' : part.result.toString()}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (part.status == ToolCallStatus.error &&
                      part.errorMessage != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      part.errorMessage!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    // 错误恢复建议
                    if (part.recoverySuggestions != null &&
                        part.recoverySuggestions!.isNotEmpty)
                      ErrorRecoverySuggestions(
                        suggestions: part.recoverySuggestions!,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 三级思考块 —— 使用增强版 ThinkingPartRenderer，支持流式脉冲点
  Widget _buildTertiaryThinking(
      BuildContext context, ThinkingPart part, bool isStreaming) {
    return ThinkingPartRenderer(
      part: part,
      collapsed: uiState.collapsedThinkingIds.contains(part.id),
      onToggleCollapse: () => updateUIState(uiState.toggleThinking(part.id)),
      isStreaming: isStreaming,
    );
  }

  /// 格式化参数为简短字符串
  String _formatArgs(Map<String, dynamic> args) {
    if (args.isEmpty) return '{}';
    return args.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ')
        .toString();
  }
}

/// 视觉层级枚举
enum _Tier {
  /// 一级：用户消息 + 助手最终回答
  primary,

  /// 二级：子助手结果
  secondary,

  /// 三级：工具调用/思考
  tertiary,
}
