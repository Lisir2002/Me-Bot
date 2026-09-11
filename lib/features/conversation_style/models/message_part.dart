/// 消息角色枚举
///
/// 定义对话中消息的发送者角色，所有样式共享此枚举。
enum MessageRole {
  /// 用户消息
  user,

  /// 助手消息
  assistant,

  /// 系统消息
  system,

  /// 工具返回结果消息
  tool,
}

/// 工具调用状态
enum ToolCallStatus {
  /// 等待执行
  pending,

  /// 执行中
  running,

  /// 执行成功
  success,

  /// 执行失败
  error,

  /// 已取消
  cancelled,
}

/// 任务状态（Todo List 子任务）
///
/// 参考 Windsurf Cascade 的 Todo List 设计：
/// ⬜ pending / ⏳ inProgress / ☑ completed / ✗ failed
enum TaskStatus {
  /// 待执行
  pending,

  /// 执行中
  inProgress,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已跳过
  skipped,
}

/// 信心等级（Devin 风格交通灯指示器）
///
/// Agent 在关键决策点自我评估信心，低信心时暂停等待用户确认。
enum ConfidenceLevel {
  /// 高信心 🟢
  high,

  /// 中信心 🟡
  medium,

  /// 低信心 🔴（建议暂停等待确认）
  low,
}

/// 审批状态
enum ApprovalStatus {
  /// 待审批
  pending,

  /// 已通过
  approved,

  /// 已拒绝
  rejected,
}

/// 产物类型
enum ArtifactType {
  /// 文档
  document,

  /// 代码
  code,

  /// 图片
  image,

  /// 图表
  chart,

  /// 网页
  web,

  /// 表格
  table,
}

/// 连接状态
enum ConnectionStatus {
  /// 已连接
  connected,

  /// 连接中
  connecting,

  /// 已断开
  disconnected,

  /// 重连中
  reconnecting,
}

/// 消息发送状态（错误恢复体验）
enum MessageSendStatus {
  /// 已发送/已落库
  sent,

  /// 发送中（等待响应）
  sending,

  /// 发送失败（可重试）
  failed,

  /// 待发送（离线排队）
  pending,
}

/// 文本实体类型（用于富文本渲染）
enum TextEntityType {
  /// 加粗
  bold,

  /// 斜体
  italic,

  /// 删除线
  strikethrough,

  /// 行内代码
  code,

  /// 链接
  link,

  /// 标题
  heading,

  /// 列表项
  listItem,

  /// 引用
  quote,
}

/// 文本实体 —— 描述文本中的格式化片段
class TextEntity {
  /// 实体类型
  final TextEntityType type;

  /// 在文本中的起始偏移
  final int offset;

  /// 实体长度
  final int length;

  /// 附加数据（如链接 URL）
  final String? data;

  const TextEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'offset': offset,
        'length': length,
        if (data != null) 'data': data,
      };

  factory TextEntity.fromJson(Map<String, dynamic> json) => TextEntity(
        type: TextEntityType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => TextEntityType.bold,
        ),
        offset: json['offset'] as int,
        length: json['length'] as int,
        data: json['data'] as String?,
      );
}

/// 消息部分基类 —— 一条消息由一个或多个 MessagePart 组成
///
/// 这是整个样式系统的统一数据模型。所有 15 种样式都基于此模型渲染，
/// 切换样式时数据完全不变。
sealed class MessagePart {
  /// 部分的唯一标识
  String get id;

  /// 转换为 JSON（用于持久化和测试）
  Map<String, dynamic> toJson();
}

/// 文本部分
class TextPart extends MessagePart {
  @override
  final String id;

  /// 文本内容
  final String text;

  /// 文本实体列表（加粗、链接、代码等格式化信息）
  final List<TextEntity>? entities;

  TextPart({
    String? id,
    required this.text,
    this.entities,
  }) : id = id ?? 'text_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'id': id,
        'text': text,
        if (entities != null)
          'entities': entities!.map((e) => e.toJson()).toList(),
      };

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        id: json['id'] as String?,
        text: json['text'] as String,
        entities: (json['entities'] as List?)
            ?.map((e) => TextEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 代码部分
class CodePart extends MessagePart {
  @override
  final String id;

  /// 代码内容
  final String code;

  /// 编程语言
  final String language;

  /// 文件名（如有）
  final String? filename;

  CodePart({
    String? id,
    required this.code,
    this.language = 'plaintext',
    this.filename,
  }) : id = id ?? 'code_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code',
        'id': id,
        'code': code,
        'language': language,
        if (filename != null) 'filename': filename,
      };

  factory CodePart.fromJson(Map<String, dynamic> json) => CodePart(
        id: json['id'] as String?,
        code: json['code'] as String,
        language: json['language'] as String? ?? 'plaintext',
        filename: json['filename'] as String?,
      );
}

/// 工具调用部分
class ToolCallPart extends MessagePart {
  @override
  final String id;

  /// 工具名称
  final String toolName;

  /// 工具调用参数
  final Map<String, dynamic> arguments;

  /// 调用状态
  final ToolCallStatus status;

  /// 执行结果
  final dynamic result;

  /// 执行耗时
  final Duration? duration;

  /// 思考过程（工具选择的推理）
  final String? thinking;

  /// 错误信息（status 为 error 时）
  final String? errorMessage;

  /// 执行进度（0.0 - 1.0，长时间运行工具使用）
  ///
  /// 参考 Claude Code 的 `████░░░░ 65%` 进度条设计，
  /// 缓解长时间工具调用的等待焦虑。
  final double? progress;

  /// 错误恢复建议（status 为 error 时提供可操作建议）
  ///
  /// 参考 Claude Code 的错误建议化设计：
  /// 错误卡片不只报错，还给出 "Check file path spelling" 等可操作建议。
  final List<String>? recoverySuggestions;

  /// Agent 对此次工具调用结果的信心评估
  ///
  /// 参考 Devin 的信心指示器：🟢🟡🔴 交通灯系统，
  /// 低信心时建议暂停等待用户确认。
  final ConfidenceLevel? confidence;

  /// 是否停滞（超过阈值无更新时标记）
  ///
  /// 参考 Cursor 社区反馈的 "spinner 永不停转" 问题：
  /// 30 秒无进展应显示 "仍在运行？" + 取消按钮。
  final bool isStalled;

  ToolCallPart({
    String? id,
    required this.toolName,
    this.arguments = const {},
    this.status = ToolCallStatus.pending,
    this.result,
    this.duration,
    this.thinking,
    this.errorMessage,
    this.progress,
    this.recoverySuggestions,
    this.confidence,
    this.isStalled = false,
  }) : id = id ?? 'tool_${DateTime.now().microsecondsSinceEpoch}';

  /// 是否处于终态
  bool get isCompleted =>
      status == ToolCallStatus.success ||
      status == ToolCallStatus.error ||
      status == ToolCallStatus.cancelled;

  ToolCallPart copyWith({
    ToolCallStatus? status,
    dynamic result,
    Duration? duration,
    String? errorMessage,
    String? thinking,
    double? progress,
    List<String>? recoverySuggestions,
    ConfidenceLevel? confidence,
    bool? isStalled,
  }) {
    return ToolCallPart(
      id: id,
      toolName: toolName,
      arguments: arguments,
      status: status ?? this.status,
      result: result ?? this.result,
      duration: duration ?? this.duration,
      thinking: thinking ?? this.thinking,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      recoverySuggestions: recoverySuggestions ?? this.recoverySuggestions,
      confidence: confidence ?? this.confidence,
      isStalled: isStalled ?? this.isStalled,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tool_call',
        'id': id,
        'toolName': toolName,
        'arguments': arguments,
        'status': status.name,
        if (result != null) 'result': result.toString(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (thinking != null) 'thinking': thinking,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (progress != null) 'progress': progress,
        if (recoverySuggestions != null)
          'recoverySuggestions': recoverySuggestions,
        if (confidence != null) 'confidence': confidence!.name,
        if (isStalled) 'isStalled': true,
      };

  factory ToolCallPart.fromJson(Map<String, dynamic> json) => ToolCallPart(
        id: json['id'] as String?,
        toolName: json['toolName'] as String,
        arguments:
            (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
        status: ToolCallStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ToolCallStatus.pending,
        ),
        result: json['result'],
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        thinking: json['thinking'] as String?,
        errorMessage: json['errorMessage'] as String?,
        progress: (json['progress'] as num?)?.toDouble(),
        recoverySuggestions: (json['recoverySuggestions'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        confidence: json['confidence'] != null
            ? ConfidenceLevel.values.firstWhere(
                (e) => e.name == json['confidence'],
                orElse: () => ConfidenceLevel.high,
              )
            : null,
        isStalled: json['isStalled'] as bool? ?? false,
      );
}

/// 图片部分
class ImagePart extends MessagePart {
  @override
  final String id;

  /// 图片 URL（本地路径或网络地址）
  final String url;

  /// 图片说明
  final String? caption;

  /// 宽度
  final int? width;

  /// 高度
  final int? height;

  ImagePart({
    String? id,
    required this.url,
    this.caption,
    this.width,
    this.height,
  }) : id = id ?? 'image_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image',
        'id': id,
        'url': url,
        if (caption != null) 'caption': caption,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  factory ImagePart.fromJson(Map<String, dynamic> json) => ImagePart(
        id: json['id'] as String?,
        url: json['url'] as String,
        caption: json['caption'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
      );
}

/// 文件部分
class FilePart extends MessagePart {
  @override
  final String id;

  /// 文件名
  final String name;

  /// 文件 URL（本地路径或网络地址）
  final String url;

  /// 文件大小（字节）
  final int size;

  /// MIME 类型
  final String mimeType;

  FilePart({
    String? id,
    required this.name,
    required this.url,
    required this.size,
    this.mimeType = 'application/octet-stream',
  }) : id = id ?? 'file_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'file',
        'id': id,
        'name': name,
        'url': url,
        'size': size,
        'mimeType': mimeType,
      };

  factory FilePart.fromJson(Map<String, dynamic> json) => FilePart(
        id: json['id'] as String?,
        name: json['name'] as String,
        url: json['url'] as String,
        size: json['size'] as int,
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      );
}

/// 思考部分
class ThinkingPart extends MessagePart {
  @override
  final String id;

  /// 思考内容
  final String content;

  /// Token 消耗数
  final int? tokenCount;

  /// 思考耗时
  final Duration? duration;

  ThinkingPart({
    String? id,
    required this.content,
    this.tokenCount,
    this.duration,
  }) : id = id ?? 'thinking_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'thinking',
        'id': id,
        'content': content,
        if (tokenCount != null) 'tokenCount': tokenCount,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
      };

  factory ThinkingPart.fromJson(Map<String, dynamic> json) => ThinkingPart(
        id: json['id'] as String?,
        content: json['content'] as String,
        tokenCount: json['tokenCount'] as int?,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
      );
}

/// 审批请求部分
class ApprovalPart extends MessagePart {
  @override
  final String id;

  /// 操作类型标识
  final String action;

  /// 操作描述
  final String description;

  /// 审批状态
  final ApprovalStatus status;

  /// 详细信息
  final Map<String, dynamic> details;

  /// 拒绝原因（用户拒绝时填写，发送给模型作为反馈）
  ///
  /// 参考 Claude Code 的拒绝反馈通道：
  /// 拒绝时用户输入的文本会作为原因发送给模型（如 "use rg instead"），
  /// 比简单 y/n 更有引导价值。
  final String? rejectReason;

  /// 是否本会话始终允许此类操作
  ///
  /// 参考 Claude Code 的 `a`（本会话允许）选项：
  /// 避免重复审批同类操作。
  final bool allowSession;

  ApprovalPart({
    String? id,
    required this.action,
    required this.description,
    this.status = ApprovalStatus.pending,
    this.details = const {},
    this.rejectReason,
    this.allowSession = false,
  }) : id = id ?? 'approval_${DateTime.now().microsecondsSinceEpoch}';

  ApprovalPart copyWith({
    ApprovalStatus? status,
    String? rejectReason,
    bool? allowSession,
  }) =>
      ApprovalPart(
        id: id,
        action: action,
        description: description,
        status: status ?? this.status,
        details: details,
        rejectReason: rejectReason ?? this.rejectReason,
        allowSession: allowSession ?? this.allowSession,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'approval',
        'id': id,
        'action': action,
        'description': description,
        'status': status.name,
        'details': details,
        if (rejectReason != null) 'rejectReason': rejectReason,
        if (allowSession) 'allowSession': true,
      };

  factory ApprovalPart.fromJson(Map<String, dynamic> json) => ApprovalPart(
        id: json['id'] as String?,
        action: json['action'] as String,
        description: json['description'] as String,
        status: ApprovalStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ApprovalStatus.pending,
        ),
        details:
            (json['details'] as Map?)?.cast<String, dynamic>() ?? const {},
        rejectReason: json['rejectReason'] as String?,
        allowSession: json['allowSession'] as bool? ?? false,
      );
}

/// 产物部分（Canvas/Artifact）
class ArtifactPart extends MessagePart {
  @override
  final String id;

  /// 产物唯一标识
  final String artifactId;

  /// 产物类型
  final ArtifactType type;

  /// 产物标题
  final String title;

  /// 产物内容预览（文本摘要或代码片段）
  final String? preview;

  ArtifactPart({
    String? id,
    required this.artifactId,
    required this.type,
    required this.title,
    this.preview,
  }) : id = id ?? 'artifact_${DateTime.now().microsecondsSinceEpoch}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'artifact',
        'id': id,
        'artifactId': artifactId,
        'artifactType': type.name,
        'title': title,
        if (preview != null) 'preview': preview,
      };

  factory ArtifactPart.fromJson(Map<String, dynamic> json) => ArtifactPart(
        id: json['id'] as String?,
        artifactId: json['artifactId'] as String,
        type: ArtifactType.values.firstWhere(
          (e) => e.name == (json['artifactType'] ?? json['type']),
          orElse: () => ArtifactType.document,
        ),
        title: json['title'] as String,
        preview: json['preview'] as String?,
      );
}

/// 任务子项（Todo List）
///
/// 参考 Windsurf Cascade 的 Todo List 设计：
/// 在对话流中嵌入可勾选的任务列表，每项 ⬜/⏳/☑/✗ 状态。
/// 用户可直接对话修改列表。这是最轻量的任务分解可视化。
///
/// 用于 Agent 三层级样式的中间层：
/// 第一层 = 总体目标，第二层 = 可勾选子任务列表，第三层 = 具体工具调用卡片。
class TaskPart extends MessagePart {
  @override
  final String id;

  /// 任务标题
  final String title;

  /// 任务描述（可选）
  final String? description;

  /// 任务状态
  final TaskStatus status;

  /// 关联的工具调用 ID 列表（此任务由哪些工具调用完成）
  final List<String>? relatedToolCallIds;

  /// 任务耗时
  final Duration? duration;

  TaskPart({
    String? id,
    required this.title,
    this.description,
    this.status = TaskStatus.pending,
    this.relatedToolCallIds,
    this.duration,
  }) : id = id ?? 'task_${DateTime.now().microsecondsSinceEpoch}';

  /// 是否完成
  bool get isCompleted => status == TaskStatus.completed;

  /// 是否进行中
  bool get isInProgress => status == TaskStatus.inProgress;

  TaskPart copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    List<String>? relatedToolCallIds,
    Duration? duration,
  }) {
    return TaskPart(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      relatedToolCallIds: relatedToolCallIds ?? this.relatedToolCallIds,
      duration: duration ?? this.duration,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'task',
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        'status': status.name,
        if (relatedToolCallIds != null)
          'relatedToolCallIds': relatedToolCallIds,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
      };

  factory TaskPart.fromJson(Map<String, dynamic> json) => TaskPart(
        id: json['id'] as String?,
        title: json['title'] as String,
        description: json['description'] as String?,
        status: TaskStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TaskStatus.pending,
        ),
        relatedToolCallIds: (json['relatedToolCallIds'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
      );
}

/// 从 JSON 反序列化 MessagePart
MessagePart messagePartFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  switch (type) {
    case 'text':
      return TextPart.fromJson(json);
    case 'code':
      return CodePart.fromJson(json);
    case 'tool_call':
      return ToolCallPart.fromJson(json);
    case 'image':
      return ImagePart.fromJson(json);
    case 'file':
      return FilePart.fromJson(json);
    case 'thinking':
      return ThinkingPart.fromJson(json);
    case 'approval':
      return ApprovalPart.fromJson(json);
    case 'artifact':
      return ArtifactPart.fromJson(json);
    case 'task':
      return TaskPart.fromJson(json);
    default:
      return TextPart(text: 'Unknown part type: $type');
  }
}
