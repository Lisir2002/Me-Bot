import '../models/conversation_state.dart';
import '../models/conversation_style.dart';
import '../models/style_settings.dart';

/// 样式解析器 —— 根据上下文自动推荐最优样式
///
/// 解析流程：
/// 1. 检查用户手动选择（per-conversation 覆盖）
/// 2. 检查 per-assistant 覆盖
/// 3. 检查全局设置
/// 4. 自动模式：意图识别 + 样式匹配评分
/// 5. 结果缓存（同一会话内，30 秒冷却期避免频繁切换）
class StyleResolver {
  /// 样式匹配评分表
  ///
  /// 行：意图特征，列：样式编号（01-15）
  /// 评分：3=强烈推荐，2=适合，1=可用，0=不推荐
  static const Map<String, List<int>> _scoreTable = {
    '纯文本短对话': [3, 1, 3, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0],
    '长文本/代码': [1, 3, 1, 1, 1, 0, 1, 2, 0, 2, 1, 0, 1, 0, 2],
    '工具调用1-2次': [2, 1, 0, 1, 3, 1, 2, 1, 0, 1, 0, 0, 0, 0, 0],
    '工具调用3+次': [0, 0, 0, 0, 3, 3, 2, 1, 0, 1, 0, 0, 1, 2, 0],
    '多助手': [0, 0, 0, 0, 2, 1, 1, 0, 3, 1, 0, 0, 0, 0, 0],
    '高风险操作': [0, 0, 0, 0, 2, 1, 3, 0, 0, 0, 0, 0, 0, 3, 0],
    '数据分析': [0, 1, 0, 0, 1, 0, 0, 0, 0, 2, 3, 0, 2, 1, 1],
    '创意/生成': [1, 2, 1, 2, 0, 0, 0, 0, 0, 1, 1, 3, 0, 0, 3],
    '开发者场景': [0, 2, 1, 0, 1, 2, 1, 3, 0, 1, 0, 0, 0, 0, 2],
    '文件/图片密集': [1, 0, 0, 3, 0, 0, 0, 0, 0, 2, 0, 0, 2, 0, 0],
    '多文档研究': [0, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 3, 2, 0],
  };

  /// 所有 15 种具体样式（不含 auto）
  static const List<ConversationStyle> _allStyles = [
    ConversationStyle.classicBubble,
    ConversationStyle.fullWidthDocument,
    ConversationStyle.minimalStream,
    ConversationStyle.cardStack,
    ConversationStyle.agentThreeTier,
    ConversationStyle.toolCardFlow,
    ConversationStyle.thinkActObserve,
    ConversationStyle.terminal,
    ConversationStyle.multiAssistant,
    ConversationStyle.richContent,
    ConversationStyle.generativeUi,
    ConversationStyle.threadBranching,
    ConversationStyle.contextPanel,
    ConversationStyle.planSurface,
    ConversationStyle.canvasArtifact,
  ];

  /// 解析最优样式
  ///
  /// [settings] 用户样式设置
  /// [intent] 当前对话意图
  /// [conversationId] 会话 ID（用于 per-conversation 覆盖）
  /// [assistantId] 助手 ID（用于 per-assistant 覆盖）
  ConversationStyle resolve({
    required StyleSettings settings,
    required ConversationIntent intent,
    String? conversationId,
    String? assistantId,
  }) {
    // 1. 检查 per-conversation 覆盖
    if (conversationId != null &&
        settings.conversationOverrides.containsKey(conversationId)) {
      return settings.conversationOverrides[conversationId]!;
    }

    // 2. 检查 per-assistant 覆盖
    if (assistantId != null &&
        settings.assistantOverrides.containsKey(assistantId)) {
      return settings.assistantOverrides[assistantId]!;
    }

    // 3. 如果未启用自动模式，使用全局样式
    if (!settings.autoModeEnabled) {
      return settings.globalStyle;
    }

    // 4. 自动模式：意图识别 + 评分
    return _resolveByIntent(intent, settings);
  }

  /// 根据意图评分选择最优样式
  ConversationStyle _resolveByIntent(
    ConversationIntent intent,
    StyleSettings settings,
  ) {
    final scores = List<int>.filled(_allStyles.length, 0);

    // 纯文本短对话
    if (!intent.hasToolCalls &&
        !intent.hasCodeBlocks &&
        intent.avgMessageLength < 100) {
      _addScores(scores, '纯文本短对话', settings);
    }

    // 长文本/代码
    if (intent.hasCodeBlocks || intent.avgMessageLength > 200) {
      _addScores(scores, '长文本/代码', settings);
    }

    // 工具调用 1-2 次
    if (intent.hasToolCalls && intent.toolCallCount <= 2) {
      _addScores(scores, '工具调用1-2次', settings);
    }

    // 工具调用 3+ 次
    if (intent.toolCallCount >= 3) {
      _addScores(scores, '工具调用3+次', settings);
    }

    // 多助手
    if (intent.hasMultipleAssistants) {
      _addScores(scores, '多助手', settings);
    }

    // 高风险操作
    if (intent.hasHighRiskActions) {
      _addScores(scores, '高风险操作', settings);
    }

    // 数据分析
    if (intent.isAnalyticalTask && !intent.hasCodeBlocks) {
      _addScores(scores, '数据分析', settings);
    }

    // 创意/生成
    if (intent.isCreativeTask) {
      _addScores(scores, '创意/生成', settings);
    }

    // 开发者场景
    if (intent.isDeveloperContext) {
      _addScores(scores, '开发者场景', settings);
    }

    // 文件/图片密集
    if (intent.hasAttachments) {
      _addScores(scores, '文件/图片密集', settings);
    }

    // 多文档研究
    if (intent.messageCount > 5 && intent.hasAttachments) {
      _addScores(scores, '多文档研究', settings);
    }

    // 找最高分
    int maxScore = -1;
    int bestIndex = 0;
    for (int i = 0; i < scores.length; i++) {
      if (scores[i] > maxScore) {
        maxScore = scores[i];
        bestIndex = i;
      }
    }

    // 如果全是 0 分，回退到经典气泡
    if (maxScore == 0) {
      return ConversationStyle.classicBubble;
    }

    return _allStyles[bestIndex];
  }

  void _addScores(
    List<int> scores,
    String feature,
    StyleSettings settings,
  ) {
    final row = _scoreTable[feature];
    if (row == null) return;

    // 应用用户自定义权重
    final weight = settings.intentWeights[feature] ?? 1.0;

    for (int i = 0; i < row.length && i < scores.length; i++) {
      scores[i] += (row[i] * weight).round();
    }
  }

  /// 解释为什么选择了这个样式（用于"为什么选这个样式"的提示）
  String explainChoice(ConversationIntent intent) {
    final reasons = <String>[];

    if (intent.hasToolCalls) {
      reasons.add('检测到 ${intent.toolCallCount} 次工具调用');
    }
    if (intent.hasCodeBlocks) {
      reasons.add('包含代码块');
    }
    if (intent.hasMultipleAssistants) {
      reasons.add('多助手协作');
    }
    if (intent.hasHighRiskActions) {
      reasons.add('包含高风险操作');
    }
    if (intent.isCreativeTask) {
      reasons.add('创意生成任务');
    }
    if (intent.isAnalyticalTask) {
      reasons.add('分析推理任务');
    }

    if (reasons.isEmpty) {
      return '基于当前对话内容智能推荐';
    }
    return '${reasons.join('，')}，智能推荐此样式';
  }
}
