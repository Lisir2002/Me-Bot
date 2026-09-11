import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/models/chat_message.dart' as hive;
import '../data/conversation_data_source.dart';
import '../models/conversation_state.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';

/// 基于 Hive 的对话数据源实现
///
/// 桥接现有的 ChatMessage Hive 模型和新的 Message + MessagePart 模型。
/// 现有 ChatMessage 的 content 字段迁移为 TextPart，
/// reasoningText 迁移为 ThinkingPart。
///
/// 这是渐进式迁移的关键：不改变现有存储，只在数据源层做模型转换。
class HiveConversationDataSource extends ChangeNotifier
    implements ConversationDataSource {
  @override
  final String conversationId;

  /// 内部消息列表（新模型）
  final List<Message> _messages = [];

  /// 会话状态
  ConversationState _state = ConversationState.idle;

  /// 流控制器
  final StreamController<List<Message>> _messageController =
      StreamController<List<Message>>.broadcast();
  final StreamController<ConversationState> _stateController =
      StreamController<ConversationState>.broadcast();

  HiveConversationDataSource({
    required this.conversationId,
    List<hive.ChatMessage>? initialMessages,
  }) {
    if (initialMessages != null) {
      _messages.addAll(initialMessages.map(_convertFromHive));
    }
    _emitMessages();
  }

  /// 从现有 Hive ChatMessage 转换为新 Message 模型
  Message _convertFromHive(hive.ChatMessage msg) {
    final parts = <MessagePart>[];

    // 思考过程 → ThinkingPart
    if (msg.reasoningText != null && msg.reasoningText!.isNotEmpty) {
      parts.add(ThinkingPart(
        content: msg.reasoningText!,
        duration: msg.reasoningStartAt != null && msg.reasoningFinishedAt != null
            ? msg.reasoningFinishedAt!.difference(msg.reasoningStartAt!)
            : null,
      ));
    }

    // 主内容 → TextPart
    if (msg.content.isNotEmpty) {
      parts.add(TextPart(text: msg.content));
    }

    return Message(
      id: msg.id,
      role: msg.role == 'user' ? MessageRole.user : MessageRole.assistant,
      parts: parts,
      timestamp: msg.timestamp,
      modelId: msg.modelId,
      isStreaming: msg.isStreaming,
      groupId: msg.groupId,
      version: msg.version,
      totalTokens: msg.totalTokens,
    );
  }

  @override
  Stream<List<Message>> get messageStream => _messageController.stream;

  @override
  Stream<ConversationState> get stateStream => _stateController.stream;

  @override
  ConversationState get currentState => _state;

  @override
  List<Message> get currentMessages => List.unmodifiable(_messages);

  @override
  Future<Message?> getMessage(String messageId) async {
    try {
      return _messages.firstWhere((m) => m.id == messageId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Message>> getMessages({
    DateTime? before,
    int limit = 50,
  }) async {
    var result = _messages;
    if (before != null) {
      result = result.where((m) => m.timestamp.isBefore(before)).toList();
    }
    return result.take(limit).toList();
  }

  @override
  Future<void> sendMessage({
    required String content,
    List<Attachment>? attachments,
    String? referencedMessageId,
  }) async {
    // 创建用户消息
    final userMsg = Message(
      role: MessageRole.user,
      parts: [
        TextPart(text: content),
        if (attachments != null)
          ...attachments.map((a) => FilePart(
                name: a.name,
                url: a.path,
                size: a.size,
                mimeType: a.mimeType,
              )),
      ],
      referencedMessageId: referencedMessageId,
    );

    _messages.add(userMsg);
    _emitMessages();

    // 更新状态为生成中
    _state = _state.copyWith(
      isGenerating: true,
      currentPhase: '正在生成...',
      lastMessageAt: DateTime.now(),
    );
    _emitState();

    // 注意：实际的 API 调用由现有的 chat_service 处理，
    // 这里只更新数据源状态。实际集成时需要桥接 chat_service 的流。
  }

  @override
  Future<void> retryMessage(String messageId) async {
    // 找到消息并标记为重新生成
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    _state = _state.copyWith(isGenerating: true, currentPhase: '重新生成中...');
    _emitState();
  }

  @override
  Future<void> stopGeneration() async {
    _state = _state.copyWith(
      isGenerating: false,
      generatingMessageId: null,
      currentPhase: null,
    );
    _emitState();

    // 标记流式消息为完成
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].isStreaming) {
        _messages[i] = _messages[i].copyWith(isStreaming: false);
      }
    }
    _emitMessages();
  }

  @override
  Future<void> approveAction(String approvalId) async {
    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final approvalIndex =
          msg.parts.indexWhere((p) => p is ApprovalPart && p.id == approvalId);
      if (approvalIndex != -1) {
        final approval = msg.parts[approvalIndex] as ApprovalPart;
        final newParts = List<MessagePart>.from(msg.parts);
        newParts[approvalIndex] = approval.copyWith(status: ApprovalStatus.approved);
        _messages[i] = msg.copyWith(parts: newParts);
      }
    }
    _emitMessages();
  }

  @override
  Future<void> rejectAction(String approvalId, {String? reason}) async {
    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final approvalIndex =
          msg.parts.indexWhere((p) => p is ApprovalPart && p.id == approvalId);
      if (approvalIndex != -1) {
        final approval = msg.parts[approvalIndex] as ApprovalPart;
        final newParts = List<MessagePart>.from(msg.parts);
        newParts[approvalIndex] = approval.copyWith(status: ApprovalStatus.rejected);
        _messages[i] = msg.copyWith(parts: newParts);
      }
    }
    _emitMessages();
  }

  @override
  Future<void> onStyleWillChange(ConversationStyle newStyle) async {
    // 数据源不关心样式，只记录切换事件
    debugPrint('[DataSource] Style will change to: $newStyle');
  }

  @override
  Future<void> onStyleDidChange(ConversationStyle style) async {
    debugPrint('[DataSource] Style did change to: $style');
  }

  /// 追加或更新消息（由外部 chat_service 流调用）
  void upsertMessage(Message message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _messages[index] = message;
    } else {
      _messages.add(message);
    }
    _emitMessages();
  }

  /// 追加消息部分（流式输出时使用）
  void appendToMessage(String messageId, MessagePart part) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final msg = _messages[index];
    // 检查是否是同类型的文本部分（流式追加）
    if (part is TextPart && msg.parts.isNotEmpty) {
      final lastPart = msg.parts.last;
      if (lastPart is TextPart) {
        final newParts = List<MessagePart>.from(msg.parts);
        newParts[newParts.length - 1] = TextPart(
          id: lastPart.id,
          text: lastPart.text + part.text,
        );
        _messages[index] = msg.copyWith(parts: newParts);
        _emitMessages();
        return;
      }
    }

    final newParts = List<MessagePart>.from(msg.parts)..add(part);
    _messages[index] = msg.copyWith(parts: newParts);
    _emitMessages();
  }

  /// 更新会话状态
  void updateState(ConversationState newState) {
    _state = newState;
    _emitState();
  }

  void _emitMessages() {
    if (!_messageController.isClosed) {
      _messageController.add(List.unmodifiable(_messages));
    }
    notifyListeners();
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  @override
  void dispose() {
    _messageController.close();
    _stateController.close();
    super.dispose();
  }
}
