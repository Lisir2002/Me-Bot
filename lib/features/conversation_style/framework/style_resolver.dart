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
  /// 用户行为统计（可选）：叠加在意图评分之上的偏好权重
  StyleUsageStats? stats;

  StyleResolver({this.stats});

  /// 样式匹配评分表
  ///
  /// 行：意图特征，列：保留的 9 种样式
  /// （classicBubble, fullWidthDocument, minimalStream, cardStack,
  ///   agentThreeTier, toolCardFlow, thinkActObserve, terminal, richContent）
  /// 评分：3=强烈推荐，2=适合，1=可用，0=不推荐
  static const Map<String, List<int>> _scoreTable = {
    '纯文本短对话': [3, 1, 3, 1, 0, 0, 0, 0, 1],
    '长文本/代码': [1, 3, 1, 1, 1, 0, 1, 2, 2],
    '工具调用1-2次': [2, 1, 0, 1, 3, 1, 2, 1, 1],
    '工具调用3+次': [0, 0, 0, 0, 3, 3, 2, 1, 1],
    '多助手': [0, 0, 0, 0, 2, 1, 1, 0, 1],
    '高风险操作': [0, 0, 0, 0, 2, 1, 3, 0, 0],
    '数据分析': [0, 1, 0, 0, 1, 0, 0, 0, 2],
    '创意/生成': [1, 2, 1, 2, 0, 0, 0, 0, 1],
    '开发者场景': [0, 2, 1, 0, 1, 2, 1, 3, 1],
    '文件/图片密集': [1, 0, 0, 3, 0, 0, 0, 0, 2],
    '多文档研究': [0, 1, 0, 1, 1, 1, 1, 0, 1],
  };

  /// 所有 9 种具体样式（不含 auto）
  static const List<ConversationStyle> _allStyles = [
    ConversationStyle.classicBubble,
    ConversationStyle.fullWidthDocument,
    ConversationStyle.minimalStream,
    ConversationStyle.cardStack,
    ConversationStyle.agentThreeTier,
    ConversationStyle.toolCardFlow,
    ConversationStyle.thinkActObserve,
    ConversationStyle.terminal,
    ConversationStyle.richContent,
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

    // 叠加用户行为偏好权重：频繁被切走的样式降权，常用/时长久的升权
    if (stats != null) {
      for (var i = 0; i < scores.length; i++) {
        final w = stats!.preferenceWeight(_allStyles[i]);
        scores[i] = (scores[i] * w).round();
      }
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

  /// 综合推荐理由：对话特征 + 用户偏好
  String getRecommendationReason(
    ConversationIntent intent,
    StyleSettings settings,
  ) {
    final parts = <String>[explainChoice(intent)];
    final fav = stats?.mostUsed;
    if (fav != null) {
      final pct = stats!.usagePercent(fav);
      parts.add(
        '你最常使用「${StyleMetaRegistry.get(fav).displayName}」'
        '（${(pct * 100).round()}%）',
      );
    }
    return parts.join('；');
  }
}

/// 样式使用行为统计 —— 轻量内存模型，可序列化持久化
///
/// 记录每个样式被选中、被切走、累计使用时长，
/// 转化为 preferenceWeight 叠加到意图评分上：
/// - 频繁被用户从它切走（awayCount 高）→ 降权
/// - 被选中次数多 / 累计时长久 → 升权
class StyleUsageStats {
  /// 各样式被用户主动选中次数
  final Map<String, int> selectCount;

  /// 各样式被用户切走的次数（"不喜欢"信号）
  final Map<String, int> awayCount;

  /// 各样式累计使用秒数
  final Map<String, double> totalSeconds;

  const StyleUsageStats({
    this.selectCount = const {},
    this.awayCount = const {},
    this.totalSeconds = const {},
  });

  /// 用户主动选中某样式
  void recordSelect(ConversationStyle style) {
    selectCount[style.name] = (selectCount[style.name] ?? 0) + 1;
  }

  /// 从某样式切走
  void recordAway(ConversationStyle style) {
    awayCount[style.name] = (awayCount[style.name] ?? 0) + 1;
  }

  /// 累加使用时长
  void addDuration(ConversationStyle style, double seconds) {
    totalSeconds[style.name] = (totalSeconds[style.name] ?? 0) + seconds;
  }

  /// 偏好权重：1.0 为中性。选中多/时久升权，被切走降权。
  double preferenceWeight(ConversationStyle style) {
    final selected = selectCount[style.name] ?? 0;
    final away = awayCount[style.name] ?? 0;
    final secs = totalSeconds[style.name] ?? 0;
    double w = 1.0;
    w += (selected * 0.08); // 每次主动选中 +8%
    w -= (away * 0.12); // 每次被切走 -12%
    w += (secs / 60.0).clamp(0, 0.5); // 每累计 1 分钟 +1%，上限 +50%
    return w.clamp(0.5, 2.0);
  }

  /// 使用占比（0.0-1.0）
  double usagePercent(ConversationStyle style) {
    final total = selectCount.values.fold<int>(0, (s, e) => s + e);
    if (total == 0) return 0;
    return (selectCount[style.name] ?? 0) / total;
  }

  /// 最常被选中的样式；无数据返回 null
  ConversationStyle? get mostUsed {
    ConversationStyle? best;
    int bestCount = 0;
    for (final e in selectCount.entries) {
      if (e.value > bestCount) {
        bestCount = e.value;
        best = ConversationStyle.values
            .firstWhere((s) => s.name == e.key, orElse: () => ConversationStyle.classicBubble);
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'selectCount': selectCount,
        'awayCount': awayCount,
        'totalSeconds': totalSeconds,
      };

  factory StyleUsageStats.fromJson(Map<String, dynamic> json) =>
      StyleUsageStats(
        selectCount: (json['selectCount'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            const {},
        awayCount: (json['awayCount'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            const {},
        totalSeconds: (json['totalSeconds'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ??
            const {},
      );
}
