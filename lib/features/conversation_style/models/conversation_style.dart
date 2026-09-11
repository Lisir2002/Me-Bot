import '../../../l10n/app_localizations.dart';
import 'message_part.dart';

/// 对话样式枚举 —— 定义 9 种样式 + 自动模式
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

  /// 10 富内容渲染
  richContent,

  /// 自动模式（特殊值，由 StyleResolver 决定具体样式）
  auto,
}

/// 样式元信息（结构性字段）—— 仅保留枚举与编号。
///
/// 展示文案（名称 / 描述 / 信息密度 / 适用场景）不再硬编码在此，
/// 统一由 [ConversationStyleL10nX] 扩展通过 context.l10n 解析，
/// 供样式选择 Sheet 与设置页共同调用。
class StyleMeta {
  /// 样式枚举
  final ConversationStyle style;

  /// 编号（01-10，跳过已淘汰编号）
  final String number;

  const StyleMeta({
    required this.style,
    required this.number,
  });
}

/// 所有样式的元信息注册表
class StyleMetaRegistry {
  static const List<StyleMeta> all = [
    StyleMeta(style: ConversationStyle.classicBubble, number: '01'),
    StyleMeta(style: ConversationStyle.fullWidthDocument, number: '02'),
    StyleMeta(style: ConversationStyle.minimalStream, number: '03'),
    StyleMeta(style: ConversationStyle.cardStack, number: '04'),
    StyleMeta(style: ConversationStyle.agentThreeTier, number: '05'),
    StyleMeta(style: ConversationStyle.toolCardFlow, number: '06'),
    StyleMeta(style: ConversationStyle.thinkActObserve, number: '07'),
    StyleMeta(style: ConversationStyle.terminal, number: '08'),
    StyleMeta(style: ConversationStyle.richContent, number: '10'),
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

/// 样式展示文案的 l10n 解析扩展。
///
/// 用法（仅在 build / 回调执行时现取，禁止缓存到字段）：
/// ```dart
/// meta.style.l10nName(context.l10n)
/// ```
/// 由 context.l10n（BuildContextL10n）传入 AppLocalizations。
extension ConversationStyleL10nX on ConversationStyle {
  /// 展示名
  String l10nName(AppLocalizations l10n) => switch (this) {
        ConversationStyle.classicBubble => l10n.convStyleClassicBubbleName,
        ConversationStyle.fullWidthDocument =>
          l10n.convStyleFullWidthDocumentName,
        ConversationStyle.minimalStream => l10n.convStyleMinimalStreamName,
        ConversationStyle.cardStack => l10n.convStyleCardStackName,
        ConversationStyle.agentThreeTier =>
          l10n.convStyleAgentThreeTierName,
        ConversationStyle.toolCardFlow => l10n.convStyleToolCardFlowName,
        ConversationStyle.thinkActObserve =>
          l10n.convStyleThinkActObserveName,
        ConversationStyle.terminal => l10n.convStyleTerminalName,
        ConversationStyle.richContent => l10n.convStyleRichContentName,
        ConversationStyle.auto => '',
      };

  /// 一句话描述
  String l10nDescription(AppLocalizations l10n) => switch (this) {
        ConversationStyle.classicBubble =>
          l10n.convStyleClassicBubbleDesc,
        ConversationStyle.fullWidthDocument =>
          l10n.convStyleFullWidthDocumentDesc,
        ConversationStyle.minimalStream => l10n.convStyleMinimalStreamDesc,
        ConversationStyle.cardStack => l10n.convStyleCardStackDesc,
        ConversationStyle.agentThreeTier =>
          l10n.convStyleAgentThreeTierDesc,
        ConversationStyle.toolCardFlow =>
          l10n.convStyleToolCardFlowDesc,
        ConversationStyle.thinkActObserve =>
          l10n.convStyleThinkActObserveDesc,
        ConversationStyle.terminal => l10n.convStyleTerminalDesc,
        ConversationStyle.richContent => l10n.convStyleRichContentDesc,
        ConversationStyle.auto => '',
      };

  /// 信息密度等级
  String l10nInfoDensity(AppLocalizations l10n) => switch (this) {
        ConversationStyle.classicBubble => l10n.convStyleDensityLow,
        ConversationStyle.fullWidthDocument =>
          l10n.convStyleDensityMediumHigh,
        ConversationStyle.minimalStream => l10n.convStyleDensityLowest,
        ConversationStyle.cardStack => l10n.convStyleDensityMedium,
        ConversationStyle.agentThreeTier =>
          l10n.convStyleDensityHighCollapsible,
        ConversationStyle.toolCardFlow => l10n.convStyleDensityHighest,
        ConversationStyle.thinkActObserve => l10n.convStyleDensityHigh,
        ConversationStyle.terminal => l10n.convStyleDensityMediumHigh,
        ConversationStyle.richContent => l10n.convStyleDensityMediumHigh,
        ConversationStyle.auto => '',
      };

  /// 适用场景标签
  List<String> l10nUseCases(AppLocalizations l10n) => switch (this) {
        ConversationStyle.classicBubble => [
            l10n.convStyleTagDailyChat,
            l10n.convStyleTagShortChat,
            l10n.convStyleTagGeneral,
          ],
        ConversationStyle.fullWidthDocument => [
            l10n.convStyleTagLongText,
            l10n.convStyleTagCodeIntensive,
            l10n.convStyleTagDocGen,
          ],
        ConversationStyle.minimalStream => [
            l10n.convStyleTagQuickQA,
            l10n.convStyleTagRealtimeStream,
            l10n.convStyleTagFocusRead,
          ],
        ConversationStyle.cardStack => [
            l10n.convStyleTagFileShare,
            l10n.convStyleTagImageHeavy,
            l10n.convStyleTagVisual,
          ],
        ConversationStyle.agentThreeTier => [
            l10n.convStyleTagAgentMultiTool,
            l10n.convStyleTagComplexTask,
            l10n.convStyleTagDeepReason,
          ],
        ConversationStyle.toolCardFlow => [
            l10n.convStyleTagMultiStepWorkflow,
            l10n.convStyleTagHighObservability,
            l10n.convStyleTagDebug,
          ],
        ConversationStyle.thinkActObserve => [
            l10n.convStyleTagDeepReason,
            l10n.convStyleTagHighExplainability,
            l10n.convStyleTagAnalysis,
          ],
        ConversationStyle.terminal => [
            l10n.convStyleTagDeveloper,
            l10n.convStyleTagCodeExec,
            l10n.convStyleTagCli,
          ],
        ConversationStyle.richContent => [
            l10n.convStyleTagDiverseContent,
            l10n.convStyleTagComprehensive,
            l10n.convStyleTagRichMedia,
          ],
        ConversationStyle.auto => const [],
      };
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

  /// 发送状态（错误恢复：sending/failed/pending/sent）
  final MessageSendStatus sendStatus;

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
    this.sendStatus = MessageSendStatus.sent,
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

  /// 获取所有任务子项（Todo List）
  List<TaskPart> get tasks => parts.whereType<TaskPart>().toList();

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
    MessageSendStatus? sendStatus,
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
      sendStatus: sendStatus ?? this.sendStatus,
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
