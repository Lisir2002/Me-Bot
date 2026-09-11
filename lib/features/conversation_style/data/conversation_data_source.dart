import 'dart:async';
import '../models/conversation_style.dart';
import '../models/conversation_state.dart';
import '../models/message_part.dart';

/// 长按消息的交互动作类型（渲染器只触发，业务由宿主处理）
enum MessageAction { copy, quote, retry, share, delete }

/// 一个版本分组的快照 —— 同一 groupId 下的全部消息版本与当前选中版本。
///
/// 容器层版本导航据此判断「该组是否存在多版本可切换」，并渲染
/// 上一版 / 下一版 + "版本 i/total"。渲染器无需感知版本概念。
class ConversationVersionGroup {
  /// 分组 ID（对应 Message.groupId；为空时以消息自身 id 分组）
  final String groupId;

  /// 该组全部版本，按 Message.version 升序
  final List<Message> versions;

  /// 当前选中版本在 [versions] 中的下标
  final int selectedIndex;

  const ConversationVersionGroup({
    required this.groupId,
    required this.versions,
    required this.selectedIndex,
  });

  /// 版本总数
  int get total => versions.length;

  /// 是否存在多版本（需要显示版本导航）
  bool get hasMultiple => total > 1;

  /// 当前选中版本消息（越界时为 null）
  Message? get selectedMessage =>
      (selectedIndex >= 0 && selectedIndex < versions.length)
          ? versions[selectedIndex]
          : null;
}

/// 附件数据（发送消息时使用）
class Attachment {
  final String name;
  final String path;
  final String mimeType;
  final int size;

  const Attachment({
    required this.name,
    required this.path,
    required this.mimeType,
    this.size = 0,
  });
}

/// 对话数据源 —— 样式渲染器的唯一数据入口
///
/// 所有样式必须通过此接口获取数据和发送操作，
/// 禁止直接访问 Hive、Provider、数据库或 API。
/// 切换样式时，此实例保持不变，中间状态完整保留。
abstract class ConversationDataSource {
  /// 当前会话 ID
  String get conversationId;

  /// 消息流 —— 所有样式订阅同一个流
  ///
  /// 这是一个广播流（BehaviorSubject 语义），
  /// 新样式订阅时立即收到当前完整消息列表，
  /// 不会丢失任何已生成的内容（包括流式输出中的部分内容）。
  Stream<List<Message>> get messageStream;

  /// 会话状态流
  Stream<ConversationState> get stateStream;

  /// 当前状态（同步获取，避免异步 gap）
  ConversationState get currentState;

  /// 当前消息列表（同步获取，用于首次渲染）
  List<Message> get currentMessages;

  /// 按 ID 获取单条消息
  Future<Message?> getMessage(String messageId);

  /// 分页获取历史消息
  Future<List<Message>> getMessages({
    DateTime? before,
    int limit = 50,
  });

  /// 发送用户消息
  ///
  /// 返回后，消息会立即出现在 messageStream 中（pending 状态），
  /// 随后流式更新。所有样式都能看到完整的状态变更过程。
  Future<void> sendMessage({
    required String content,
    List<Attachment>? attachments,
    String? referencedMessageId,
  });

  /// 重试某条消息（重新生成）
  Future<void> retryMessage(String messageId);

  /// 删除某条消息（渲染层通知宿主，宿主负责真实 Hive 删除 + 同步）
  Future<void> deleteMessage(String messageId);

  /// 长按消息的交互回调（引用/分享/删除确认等），由宿主页注入，
  /// 渲染器只负责在用户长按后触发，不实现具体业务。
  void Function(Message message, MessageAction action)? get onMessageAction;
  set onMessageAction(void Function(Message message, MessageAction action)? cb);

  /// 新审批请求出现时回调宿主弹出审批对话框
  void Function(ApprovalPart approval)? get onApprovalRequired;
  set onApprovalRequired(void Function(ApprovalPart approval)? cb);

  /// 重试失败的用户消息
  Future<void> retryFailedMessage(String messageId);

  /// 继续被中断的生成
  Future<void> resumeGeneration();

  /// 标记某条消息发送失败（渲染层显示错误态）
  void markMessageFailed(String messageId, String error);

  /// 更新工具调用状态流转（queued→running→success/error）
  void updateToolCallStatus(
    String messageId,
    String toolCallId,
    ToolCallStatus status, {
    dynamic result,
    String? errorMessage,
    Duration? duration,
    List<String>? recoverySuggestions,
  });

  /// 停止当前生成
  Future<void> stopGeneration();

  /// 审批通过（高风险操作）
  Future<void> approveAction(String approvalId);

  /// 审批拒绝
  Future<void> rejectAction(String approvalId, {String? reason});

  /// 切换样式（由 StyleSwitcher 调用，数据源本身不关心样式）
  /// 此方法只通知数据源"样式即将切换"，用于暂停/恢复流式渲染优化，
  /// 不改变任何数据状态。
  Future<void> onStyleWillChange(ConversationStyle newStyle);

  /// 样式切换完成
  Future<void> onStyleDidChange(ConversationStyle style);

  /// 当前会话的全部版本分组（按展示顺序）。
  ///
  /// 容器层据此渲染版本导航；单版本分组也会出现在列表中（hasMultiple=false）。
  /// 未启用版本折叠（宿主未接入全量同步）时返回空列表。
  List<ConversationVersionGroup> get versionGroups;

  /// 上下文截断位置（折叠视图下标）。
  ///
  /// 容器层据此在消息流顶部渲染"此处之前为已截断上下文"分隔提示；
  /// null 表示当前无截断。
  int? get truncatePositionIndex;

  /// 切换某分组的选中版本（容器层"上一版 / 下一版"调用）。
  ///
  /// 实现方需更新折叠视图并重新广播消息流；同时通过 [onSelectedVersionChanged]
  /// 通知宿主持久化选中版本。versionIndex 越界时实现方自行钳制。
  Future<void> setSelectedVersion(String groupId, int versionIndex);

  /// 批量删除消息（选择模式"删除所选"）。
  ///
  /// 实现方从渲染视图中移除并重新广播；真实持久化由宿主经现有删除路径完成。
  Future<void> deleteMessages(List<String> messageIds);

  /// 分享所选消息（选择模式"分享所选"）。
  ///
  /// 实现方按 ID 解析出消息后触发 [onShareMessages] 交宿主展示分享面板；
  /// 未注入回调时静默忽略。
  Future<void> shareSelectedMessages(List<String> messageIds);

  /// 选中版本变更回调（宿主持久化，可空，默认 null）。
  ///
  /// 容器调用 [setSelectedVersion] 时触发，宿主据此把选中版本写回 Hive / 服务层。
  /// 未接线时为 null，不影响容器内的版本切换本身。
  void Function(String groupId, int versionIndex)? get onSelectedVersionChanged;
  set onSelectedVersionChanged(
      void Function(String groupId, int versionIndex)? cb);

  /// 分享所选消息回调（宿主展示分享面板，可空，默认 null）。
  void Function(List<Message> messages)? get onShareMessages;
  set onShareMessages(void Function(List<Message> messages)? cb);

  /// 释放资源（会话关闭时调用）
  void dispose();
}
