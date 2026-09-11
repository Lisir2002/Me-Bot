import 'conversation_style.dart';

/// 样式设置模型 —— 持久化用户偏好
class StyleSettings {
  /// 全局默认样式
  final ConversationStyle globalStyle;

  /// 是否启用自动模式
  final bool autoModeEnabled;

  /// 按助手覆盖（assistantId -> style）
  final Map<String, ConversationStyle> assistantOverrides;

  /// 按会话覆盖（conversationId -> style）
  final Map<String, ConversationStyle> conversationOverrides;

  /// 自动模式的意图权重调整
  final Map<String, double> intentWeights;

  /// 是否启用样式切换动画
  final bool transitionAnimationEnabled;

  const StyleSettings({
    this.globalStyle = ConversationStyle.classicBubble,
    this.autoModeEnabled = false,
    this.assistantOverrides = const {},
    this.conversationOverrides = const {},
    this.intentWeights = const {},
    this.transitionAnimationEnabled = true,
  });

  StyleSettings copyWith({
    ConversationStyle? globalStyle,
    bool? autoModeEnabled,
    Map<String, ConversationStyle>? assistantOverrides,
    Map<String, ConversationStyle>? conversationOverrides,
    Map<String, double>? intentWeights,
    bool? transitionAnimationEnabled,
  }) {
    return StyleSettings(
      globalStyle: globalStyle ?? this.globalStyle,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      assistantOverrides: assistantOverrides ?? this.assistantOverrides,
      conversationOverrides: conversationOverrides ?? this.conversationOverrides,
      intentWeights: intentWeights ?? this.intentWeights,
      transitionAnimationEnabled:
          transitionAnimationEnabled ?? this.transitionAnimationEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'globalStyle': globalStyle.name,
        'autoModeEnabled': autoModeEnabled,
        'assistantOverrides': assistantOverrides
            .map((k, v) => MapEntry(k, v.name)),
        'conversationOverrides': conversationOverrides
            .map((k, v) => MapEntry(k, v.name)),
        'intentWeights': intentWeights,
        'transitionAnimationEnabled': transitionAnimationEnabled,
      };

  factory StyleSettings.fromJson(Map<String, dynamic> json) => StyleSettings(
        globalStyle: ConversationStyle.values.firstWhere(
          (e) => e.name == json['globalStyle'],
          orElse: () => ConversationStyle.classicBubble,
        ),
        autoModeEnabled: json['autoModeEnabled'] as bool? ?? false,
        assistantOverrides: (json['assistantOverrides'] as Map?)
                ?.map((k, v) => MapEntry(
                    k.toString(),
                    ConversationStyle.values.firstWhere(
                      (e) => e.name == v,
                      orElse: () => ConversationStyle.classicBubble,
                    ))) ??
            const {},
        conversationOverrides: (json['conversationOverrides'] as Map?)
                ?.map((k, v) => MapEntry(
                    k.toString(),
                    ConversationStyle.values.firstWhere(
                      (e) => e.name == v,
                      orElse: () => ConversationStyle.classicBubble,
                    ))) ??
            const {},
        intentWeights: (json['intentWeights'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ??
            const {},
        transitionAnimationEnabled:
            json['transitionAnimationEnabled'] as bool? ?? true,
      );
}

/// 上下文面板 Tab 枚举
enum ContextPanelTab {
  /// 文件
  files,

  /// 工具
  tools,

  /// 引用来源
  sources,

  /// 模型信息
  model,
}

/// 对话 UI 状态 —— 独立于样式层，切换样式时完整保留
///
/// 数据状态由 ConversationDataSource 管理，
/// UI 状态（展开/折叠、选中标签等）由此类管理。
class ConversationUIState {
  /// 已展开的工具调用 ID 集合
  final Set<String> expandedToolCallIds;

  /// 已折叠的思考过程 ID 集合
  final Set<String> collapsedThinkingIds;

  /// 已展开的代码块 ID 集合（默认折叠长代码）
  final Set<String> expandedCodeBlockIds;

  /// 当前激活的产物 Tab（canvas 样式用）
  final String? activeArtifactTab;

  /// 当前激活的上下文面板 Tab（contextPanel 样式用）
  final ContextPanelTab activeContextPanelTab;

  /// 对话分支中当前选中的分支 ID（threadBranching 样式用）
  final String? activeBranchId;

  /// 执行计划是否已确认（planSurface 样式用）
  final bool planConfirmed;

  /// 用户手动展开的消息 ID（默认折叠的子助手消息等）
  final Set<String> expandedMessageIds;

  /// 生成式 UI 组件的交互状态（componentId -> state map）
  final Map<String, Map<String, dynamic>> generativeUiStates;

  const ConversationUIState({
    this.expandedToolCallIds = const {},
    this.collapsedThinkingIds = const {},
    this.expandedCodeBlockIds = const {},
    this.activeArtifactTab,
    this.activeContextPanelTab = ContextPanelTab.files,
    this.activeBranchId,
    this.planConfirmed = false,
    this.expandedMessageIds = const {},
    this.generativeUiStates = const {},
  });

  ConversationUIState copyWith({
    Set<String>? expandedToolCallIds,
    Set<String>? collapsedThinkingIds,
    Set<String>? expandedCodeBlockIds,
    String? activeArtifactTab,
    ContextPanelTab? activeContextPanelTab,
    String? activeBranchId,
    bool? planConfirmed,
    Set<String>? expandedMessageIds,
    Map<String, Map<String, dynamic>>? generativeUiStates,
  }) {
    return ConversationUIState(
      expandedToolCallIds: expandedToolCallIds ?? this.expandedToolCallIds,
      collapsedThinkingIds: collapsedThinkingIds ?? this.collapsedThinkingIds,
      expandedCodeBlockIds: expandedCodeBlockIds ?? this.expandedCodeBlockIds,
      activeArtifactTab: activeArtifactTab ?? this.activeArtifactTab,
      activeContextPanelTab:
          activeContextPanelTab ?? this.activeContextPanelTab,
      activeBranchId: activeBranchId ?? this.activeBranchId,
      planConfirmed: planConfirmed ?? this.planConfirmed,
      expandedMessageIds: expandedMessageIds ?? this.expandedMessageIds,
      generativeUiStates: generativeUiStates ?? this.generativeUiStates,
    );
  }

  /// 切换工具调用展开状态
  ConversationUIState toggleToolCall(String id) {
    final newSet = Set<String>.from(expandedToolCallIds);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
    }
    return copyWith(expandedToolCallIds: newSet);
  }

  /// 切换思考过程折叠状态
  ConversationUIState toggleThinking(String id) {
    final newSet = Set<String>.from(collapsedThinkingIds);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
    }
    return copyWith(collapsedThinkingIds: newSet);
  }

  /// 切换代码块展开状态
  ConversationUIState toggleCodeBlock(String id) {
    final newSet = Set<String>.from(expandedCodeBlockIds);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
    }
    return copyWith(expandedCodeBlockIds: newSet);
  }

  /// 切换消息展开状态
  ConversationUIState toggleMessage(String id) {
    final newSet = Set<String>.from(expandedMessageIds);
    if (newSet.contains(id)) {
      newSet.remove(id);
    } else {
      newSet.add(id);
    }
    return copyWith(expandedMessageIds: newSet);
  }
}
