import 'message_part.dart';

/// 任务执行模式
///
/// 参考 Cline 的 Plan/Act 双模式设计：
/// - plan：只讨论规划，不执行副作用
/// - act：执行工具调用和副作用操作
/// - auto：自动判断（简单任务直接执行，复杂任务先规划）
enum TaskExecutionMode {
  /// 规划模式：只讨论，不执行
  plan,

  /// 执行模式：执行工具调用
  act,

  /// 自动模式：自动判断
  auto,
}

/// 会话运行时状态 —— 切换样式时完整保留
///
/// 此状态独立于样式层，由 ConversationDataSource 维护。
class ConversationState {
  /// 是否正在生成回复
  final bool isGenerating;

  /// 当前正在生成的消息 ID（流式输出中的消息）
  final String? generatingMessageId;

  /// 当前生成进度（0.0 - 1.0，工具调用场景）
  final double? generationProgress;

  /// 当前阶段描述（"正在搜索..." / "正在分析..." / "正在生成..."）
  final String? currentPhase;

  /// 待审批的操作列表
  final List<ApprovalPart> pendingApprovals;

  /// 错误信息（如有）
  final ConversationError? error;

  /// 网络连接状态
  final ConnectionStatus connectionStatus;

  /// 最后一条消息的时间戳
  final DateTime? lastMessageAt;

  /// 未读消息数
  final int unreadCount;

  /// 任务执行模式（Plan/Act/Auto）
  ///
  /// 参考 Cline 的 Plan/Act 双模式：
  /// 对话流顶部加模式切换，Plan 只讨论，Act 才执行副作用。
  final TaskExecutionMode taskMode;

  /// 当前任务的总步骤数（用于流水线进度指示）
  ///
  /// 参考 LangGraph GenUI 的 PipelineProgress：
  /// 顶部横向步骤徽章，灰/蓝pulse/绿/红四色态。
  final int? totalSteps;

  /// 当前已完成的步骤数
  final int? completedSteps;

  /// 当前正在执行的步骤名称
  final String? currentStepName;

  /// 追问建议（Perplexity 风格，答案后给出 2-4 个上下文相关的追问芯片）
  final List<String> followUpSuggestions;

  const ConversationState({
    this.isGenerating = false,
    this.generatingMessageId,
    this.generationProgress,
    this.currentPhase,
    this.pendingApprovals = const [],
    this.error,
    this.connectionStatus = ConnectionStatus.connected,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.taskMode = TaskExecutionMode.auto,
    this.totalSteps,
    this.completedSteps,
    this.currentStepName,
    this.followUpSuggestions = const [],
  });

  ConversationState copyWith({
    bool? isGenerating,
    String? generatingMessageId,
    double? generationProgress,
    String? currentPhase,
    List<ApprovalPart>? pendingApprovals,
    ConversationError? error,
    ConnectionStatus? connectionStatus,
    DateTime? lastMessageAt,
    int? unreadCount,
    TaskExecutionMode? taskMode,
    int? totalSteps,
    int? completedSteps,
    String? currentStepName,
    List<String>? followUpSuggestions,
  }) {
    return ConversationState(
      isGenerating: isGenerating ?? this.isGenerating,
      generatingMessageId: generatingMessageId ?? this.generatingMessageId,
      generationProgress: generationProgress ?? this.generationProgress,
      currentPhase: currentPhase ?? this.currentPhase,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
      error: error ?? this.error,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      taskMode: taskMode ?? this.taskMode,
      totalSteps: totalSteps ?? this.totalSteps,
      completedSteps: completedSteps ?? this.completedSteps,
      currentStepName: currentStepName ?? this.currentStepName,
      followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions,
    );
  }

  /// 空闲状态
  static const ConversationState idle = ConversationState();

  /// 流水线进度百分比（0.0 - 1.0），无步骤时为 null
  double? get pipelineProgress {
    if (totalSteps == null || totalSteps == 0) return null;
    return (completedSteps ?? 0) / totalSteps!;
  }
}

/// 对话错误信息
class ConversationError {
  /// 错误码
  final String code;

  /// 错误消息
  final String message;

  /// 错误详情
  final String? details;

  /// 是否可重试
  final bool retryable;

  const ConversationError({
    required this.code,
    required this.message,
    this.details,
    this.retryable = true,
  });

  @override
  String toString() => 'ConversationError($code): $message';
}

/// 对话意图 —— 描述当前对话的特征向量，用于 StyleResolver 自动推荐
class ConversationIntent {
  /// 是否包含工具调用
  final bool hasToolCalls;

  /// 工具调用次数
  final int toolCallCount;

  /// 是否包含代码块
  final bool hasCodeBlocks;

  /// 代码块占比（0.0 - 1.0）
  final double codeBlockRatio;

  /// 是否包含附件
  final bool hasAttachments;

  /// 是否有多个助手参与
  final bool hasMultipleAssistants;

  /// 是否有高风险操作
  final bool hasHighRiskActions;

  /// 是否是创意任务
  final bool isCreativeTask;

  /// 是否是分析任务
  final bool isAnalyticalTask;

  /// 是否是开发者场景
  final bool isDeveloperContext;

  /// 消息总数
  final int messageCount;

  /// 平均消息长度
  final double avgMessageLength;

  const ConversationIntent({
    this.hasToolCalls = false,
    this.toolCallCount = 0,
    this.hasCodeBlocks = false,
    this.codeBlockRatio = 0,
    this.hasAttachments = false,
    this.hasMultipleAssistants = false,
    this.hasHighRiskActions = false,
    this.isCreativeTask = false,
    this.isAnalyticalTask = false,
    this.isDeveloperContext = false,
    this.messageCount = 0,
    this.avgMessageLength = 0,
  });

  /// 从消息列表分析意图
  factory ConversationIntent.analyze(List<dynamic> messages) {
    if (messages.isEmpty) return const ConversationIntent();

    int toolCallCount = 0;
    int codeBlockCount = 0;
    int attachmentCount = 0;
    int totalLength = 0;
    final assistantIds = <String>{};
    bool hasHighRisk = false;
    bool hasThinking = false;

    for (final msg in messages) {
      final parts = msg.parts as List;
      for (final part in parts) {
        if (part is ToolCallPart) {
          toolCallCount++;
        } else if (part is CodePart) {
          codeBlockCount++;
        } else if (part is FilePart || part is ImagePart) {
          attachmentCount++;
        } else if (part is ApprovalPart) {
          hasHighRisk = true;
        } else if (part is ThinkingPart) {
          hasThinking = true;
        }
      }
      if (msg.assistantId != null) {
        assistantIds.add(msg.assistantId as String);
      }
      totalLength += (msg.textContent?.length ?? 0) as int;
    }

    final totalParts = messages.fold<int>(
      0,
      (sum, m) => sum + (m.parts as List).length,
    );

    return ConversationIntent(
      hasToolCalls: toolCallCount > 0,
      toolCallCount: toolCallCount,
      hasCodeBlocks: codeBlockCount > 0,
      codeBlockRatio: totalParts > 0 ? codeBlockCount / totalParts : 0,
      hasAttachments: attachmentCount > 0,
      hasMultipleAssistants: assistantIds.length > 1,
      hasHighRiskActions: hasHighRisk,
      isCreativeTask: hasThinking && toolCallCount == 0,
      isAnalyticalTask: hasThinking && toolCallCount > 0,
      isDeveloperContext: codeBlockCount > 0 || toolCallCount > 0,
      messageCount: messages.length,
      avgMessageLength: messages.isNotEmpty ? totalLength / messages.length : 0,
    );
  }
}
