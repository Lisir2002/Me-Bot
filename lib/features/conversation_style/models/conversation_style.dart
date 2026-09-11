// ignore_for_file: hardcoded_ui_string
import 'message_part.dart';

/// 对话样式枚举 —— 定义 15 种样式 + 自动模式
///
/// 每种样式对应一个 StyleRenderer 实现，通过 StyleRendererRegistry 注册。
enum ConversationStyle {
  /// 01 经典气泡式（现有样式迁移）
  classicBubble,

  /// 02 全宽文档式
  fullWidthDocument,

  /// 03 极简流式
  minimalStream,

  /// 04 卡片堆叠式
  cardStack,

  /// 05 Agent 三层级（重点推荐）
  agentThreeTier,

  /// 06 工具卡片流
  toolCardFlow,

  /// 07 思考-行动-观察闭环
  thinkActObserve,

  /// 08 终端风格
  terminal,

  /// 09 多助手协作
  multiAssistant,

  /// 10 富内容渲染
  richContent,

  /// 11 生成式 UI
  generativeUi,

  /// 12 对话分支
  threadBranching,

  /// 13 上下文面板
  contextPanel,

  /// 14 执行计划面板
  planSurface,

  /// 15 画布产物
  canvasArtifact,

  /// 自动模式（特殊值，由 StyleResolver 决定具体样式）
  auto,
}

/// 样式元信息 —— 用于设置页面展示和样式选择
class StyleMeta {
  /// 样式枚举
  final ConversationStyle style;

  /// 显示名称
  final String displayName;

  /// 一句话描述
  final String description;

  /// 编号（01-15）
  final String number;

  /// 信息密度等级
  final String infoDensity;

  /// 适用场景
  final List<String> useCases;

  const StyleMeta({
    required this.style,
    required this.displayName,
    required this.description,
    required this.number,
    required this.infoDensity,
    required this.useCases,
  });
}

/// 所有样式的元信息注册表
class StyleMetaRegistry {
  static const List<StyleMeta> all = [
    StyleMeta(
      style: ConversationStyle.classicBubble,
      displayName: '经典气泡式',
      description: '用户右对齐、助手左对齐的圆角气泡，日常聊天首选',
      number: '01',
      infoDensity: '低',
      useCases: ['日常聊天', '短对话', '通用场景'],
    ),
    StyleMeta(
      style: ConversationStyle.fullWidthDocument,
      displayName: '全宽文档式',
      description: '消息占满宽度、分隔线区分，适合长文本和代码密集场景',
      number: '02',
      infoDensity: '中高',
      useCases: ['长文本', '代码密集', '文档生成'],
    ),
    StyleMeta(
      style: ConversationStyle.minimalStream,
      displayName: '极简流式',
      description: '纯文本流、无气泡无边框，最快的实时流式输出体验',
      number: '03',
      infoDensity: '最低',
      useCases: ['快速问答', '实时流式输出', '专注阅读'],
    ),
    StyleMeta(
      style: ConversationStyle.cardStack,
      displayName: '卡片堆叠式',
      description: '每条消息是带阴影的卡片，视觉层次分明',
      number: '04',
      infoDensity: '中',
      useCases: ['文件分享', '图片密集', '视觉驱动'],
    ),
    StyleMeta(
      style: ConversationStyle.agentThreeTier,
      displayName: 'Agent 三层级',
      description: '主回答/子助手结果/工具调用三级视觉层级，复杂任务首选',
      number: '05',
      infoDensity: '高（可折叠）',
      useCases: ['Agent 多工具调用', '复杂任务', '深度推理'],
    ),
    StyleMeta(
      style: ConversationStyle.toolCardFlow,
      displayName: '工具卡片流',
      description: '每个工具调用是独立卡片，纵向时间线展示执行进度',
      number: '06',
      infoDensity: '最高',
      useCases: ['复杂多步骤工作流', '可观测性要求高', '调试'],
    ),
    StyleMeta(
      style: ConversationStyle.thinkActObserve,
      displayName: '思考-行动-观察闭环',
      description: '左侧 rail 时间线，三阶段明确区分，深度推理可解释',
      number: '07',
      infoDensity: '高',
      useCases: ['深度推理', '可解释性要求高', '分析任务'],
    ),
    StyleMeta(
      style: ConversationStyle.terminal,
      displayName: '终端风格',
      description: '等宽字体、命令行风格，开发者和代码执行场景',
      number: '08',
      infoDensity: '中高',
      useCases: ['开发者', '代码执行', 'CLI 集成'],
    ),
    StyleMeta(
      style: ConversationStyle.multiAssistant,
      displayName: '多助手协作',
      description: '不同助手用颜色编码和名称标签，任务交接动画',
      number: '09',
      infoDensity: '中',
      useCases: ['多 Agent 协作', '团队讨论', '角色分工'],
    ),
    StyleMeta(
      style: ConversationStyle.richContent,
      displayName: '富内容渲染',
      description: '综合渲染，按内容类型自适应，代码/文件/表格原生渲染',
      number: '10',
      infoDensity: '中高',
      useCases: ['内容类型多样', '综合展示', '富媒体'],
    ),
    StyleMeta(
      style: ConversationStyle.generativeUi,
      displayName: '生成式 UI',
      description: '模型返回交互式组件而非纯文本，图表/表格/KPI 卡片',
      number: '11',
      infoDensity: '高（结构化）',
      useCases: ['数据分析', '报表生成', '表单填充'],
    ),
    StyleMeta(
      style: ConversationStyle.threadBranching,
      displayName: '对话分支',
      description: '从某条消息分叉出多个路径，分支对比和合并',
      number: '12',
      infoDensity: '中',
      useCases: ['创意写作', '方案对比', '头脑风暴'],
    ),
    StyleMeta(
      style: ConversationStyle.contextPanel,
      displayName: '上下文面板',
      description: '对话 + 右侧固定上下文面板，文件/工具/引用来源一览',
      number: '13',
      infoDensity: '高',
      useCases: ['多文档任务', '研究', '复杂上下文'],
    ),
    StyleMeta(
      style: ConversationStyle.planSurface,
      displayName: '执行计划面板',
      description: 'Agent 先展示执行计划，用户审核后执行，实时进度更新',
      number: '14',
      infoDensity: '高',
      useCases: ['复杂任务', '高风险操作', '需要用户确认'],
    ),
    StyleMeta(
      style: ConversationStyle.canvasArtifact,
      displayName: '画布产物',
      description: '对话 + 画布并排，代码预览/文档渲染/设计稿实时编辑',
      number: '15',
      infoDensity: '高（双区）',
      useCases: ['代码生成', '文档写作', '设计创作'],
    ),
  ];

  /// 获取指定样式的元信息
  static StyleMeta get(ConversationStyle style) {
    return all.firstWhere(
      (m) => m.style == style,
      orElse: () => all.first,
    );
  }

  /// 除自动模式外的所有样式
  static List<StyleMeta> get concreteStyles =>
      all.where((m) => m.style != ConversationStyle.auto).toList();
}

/// 统一消息模型 —— 一条消息包含角色、时间戳和多个 MessagePart
///
/// 这是从现有 ChatMessage 模型迁移而来的统一模型，
/// 所有样式都基于此模型渲染。
class Message {
  /// 消息唯一标识
  final String id;

  /// 消息角色
  final MessageRole role;

  /// 消息包含的部分列表
  final List<MessagePart> parts;

  /// 时间戳
  final DateTime timestamp;

  /// 模型 ID（助手消息）
  final String? modelId;

  /// 助手 ID（多助手场景）
  final String? assistantId;

  /// 助手名称（多助手场景显示用）
  final String? assistantName;

  /// 助手颜色标识（多助手场景，如 'blue'/'yellow'/'red'）
  final String? assistantColor;

  /// 是否正在流式输出
  final bool isStreaming;

  /// 分组 ID（对话分支场景，同一语义位置的消息共享 groupId）
  final String? groupId;

  /// 版本号（对话分支场景，同一 groupId 下的不同版本）
  final int version;

  /// 父消息 ID（对话分支场景，形成树结构）
  final String? parentId;

  /// 引用的消息 ID
  final String? referencedMessageId;

  /// Token 使用量
  final int? totalTokens;

  Message({
    String? id,
    required this.role,
    List<MessagePart>? parts,
    DateTime? timestamp,
    this.modelId,
    this.assistantId,
    this.assistantName,
    this.assistantColor,
    this.isStreaming = false,
    this.groupId,
    this.version = 0,
    this.parentId,
    this.referencedMessageId,
    this.totalTokens,
  })  : id = id ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
        parts = parts ?? [],
        timestamp = timestamp ?? DateTime.now();

  /// 获取所有文本部分的合并文本
  String get textContent => parts
      .whereType<TextPart>()
      .map((p) => p.text)
      .join('\n');

  /// 获取所有工具调用部分
  List<ToolCallPart> get toolCalls => parts.whereType<ToolCallPart>().toList();

  /// 获取所有代码部分
  List<CodePart> get codeBlocks => parts.whereType<CodePart>().toList();

  /// 获取所有思考部分
  List<ThinkingPart> get thinkingParts =>
      parts.whereType<ThinkingPart>().toList();

  /// 获取所有审批部分
  List<ApprovalPart> get approvals =>
      parts.whereType<ApprovalPart>().toList();

  /// 获取所有产物部分
  List<ArtifactPart> get artifacts =>
      parts.whereType<ArtifactPart>().toList();

  /// 获取所有图片部分
  List<ImagePart> get images => parts.whereType<ImagePart>().toList();

  /// 获取所有文件部分
  List<FilePart> get files => parts.whereType<FilePart>().toList();

  Message copyWith({
    String? id,
    MessageRole? role,
    List<MessagePart>? parts,
    DateTime? timestamp,
    String? modelId,
    String? assistantId,
    String? assistantName,
    String? assistantColor,
    bool? isStreaming,
    String? groupId,
    int? version,
    String? parentId,
    String? referencedMessageId,
    int? totalTokens,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      timestamp: timestamp ?? this.timestamp,
      modelId: modelId ?? this.modelId,
      assistantId: assistantId ?? this.assistantId,
      assistantName: assistantName ?? this.assistantName,
      assistantColor: assistantColor ?? this.assistantColor,
      isStreaming: isStreaming ?? this.isStreaming,
      groupId: groupId ?? this.groupId,
      version: version ?? this.version,
      parentId: parentId ?? this.parentId,
      referencedMessageId: referencedMessageId ?? this.referencedMessageId,
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'parts': parts.map((p) => p.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
        if (modelId != null) 'modelId': modelId,
        if (assistantId != null) 'assistantId': assistantId,
        if (assistantName != null) 'assistantName': assistantName,
        if (assistantColor != null) 'assistantColor': assistantColor,
        'isStreaming': isStreaming,
        if (groupId != null) 'groupId': groupId,
        'version': version,
        if (parentId != null) 'parentId': parentId,
        if (referencedMessageId != null)
          'referencedMessageId': referencedMessageId,
        if (totalTokens != null) 'totalTokens': totalTokens,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => MessageRole.assistant,
        ),
        parts: (json['parts'] as List?)
                ?.map((p) =>
                    messagePartFromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        timestamp: DateTime.parse(json['timestamp'] as String),
        modelId: json['modelId'] as String?,
        assistantId: json['assistantId'] as String?,
        assistantName: json['assistantName'] as String?,
        assistantColor: json['assistantColor'] as String?,
        isStreaming: json['isStreaming'] as bool? ?? false,
        groupId: json['groupId'] as String?,
        version: (json['version'] as int?) ?? 0,
        parentId: json['parentId'] as String?,
        referencedMessageId: json['referencedMessageId'] as String?,
        totalTokens: json['totalTokens'] as int?,
      );
}
