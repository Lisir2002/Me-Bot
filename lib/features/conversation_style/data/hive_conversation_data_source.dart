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

  /// 长按菜单交互回调（宿主注入）
  @override
  void Function(Message message, MessageAction action)? onMessageAction;

  /// 新审批请求出现时回调宿主（宿主注入）
  @override
  void Function(ApprovalPart approval)? onApprovalRequired;

  /// 选中版本变更回调（宿主持久化，可空）
  @override
  void Function(String groupId, int versionIndex)? onSelectedVersionChanged;

  /// 分享所选消息回调（宿主展示分享面板，可空）
  @override
  void Function(List<Message> messages)? onShareMessages;

  /// 内部消息列表（新模型，折叠后：每个版本组只占一条）
  final List<Message> _messages = [];

  /// 版本分组（展示顺序）；由 syncConversationFull / syncFromMessages 维护
  final List<_VersionEntry> _versionEntries = [];

  /// groupId -> 版本条目，便于按组快速定位
  final Map<String, _VersionEntry> _entryByGroup = {};

  /// 上下文截断位置（折叠视图下标；null 表示无截断）
  int? _truncatePositionIndex;

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

    // 主内容 → TextPart；同时解析内嵌的 [image:path] / [file:path|name|mime] 标记
    parts.addAll(_splitContent(msg.content));

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

  /// 把一段 content 文本切分为 TextPart / ImagePart / FilePart
  ///
  /// 现有消息把图片/文档以内联标记写入 content：
  /// - `[image:/abs/path.png]` → ImagePart
  /// - `[file:/abs/path|报告.pdf|application/pdf]` → FilePart
  /// 标记之外的纯文本按出现顺序聚合成 TextPart。
  List<MessagePart> _splitContent(String content) {
    if (content.isEmpty) return const [];
    // 单条组合正则：group1 = image 路径，group2 = file 内容
    final markerRe = RegExp(r'\[(?:image:([^\]]+)|file:([^\]]+))\]');
    final parts = <MessagePart>[];
    var textStart = 0;
    for (final m in markerRe.allMatches(content)) {
      final between = content.substring(textStart, m.start);
      if (between.isNotEmpty) parts.add(TextPart(text: between));

      final img = m.group(1);
      if (img != null) {
        parts.add(ImagePart(url: img.trim()));
      } else {
        final segs = (m.group(2) ?? '').split('|');
        final path = segs.isNotEmpty ? segs[0].trim() : '';
        final name = (segs.length > 1 && segs[1].trim().isNotEmpty)
            ? segs[1].trim()
            : (path.isEmpty ? 'file' : path.split('/').last);
        final mime = (segs.length > 2 && segs[2].trim().isNotEmpty)
            ? segs[2].trim()
            : 'application/octet-stream';
        parts.add(FilePart(name: name, url: path, mimeType: mime, size: 0));
      }
      textStart = m.end;
    }
    final tail = content.substring(textStart);
    if (tail.isNotEmpty) parts.add(TextPart(text: tail));
    if (parts.isEmpty) parts.add(TextPart(text: ''));
    return parts;
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
  List<ConversationVersionGroup> get versionGroups => List.unmodifiable(
        _versionEntries.map(
          (e) => ConversationVersionGroup(
            groupId: e.groupId,
            versions: List.unmodifiable(e.versions),
            selectedIndex: e.selectedIndex,
          ),
        ),
      );

  @override
  int? get truncatePositionIndex => _truncatePositionIndex;

  @override
  Future<void> setSelectedVersion(String groupId, int versionIndex) async {
    final entry = _entryByGroup[groupId];
    if (entry == null || entry.versions.isEmpty) return;
    final idx = versionIndex.clamp(0, entry.versions.length - 1);
    if (idx == entry.selectedIndex) return;
    entry.selectedIndex = idx;

    // 折叠视图：用新选中版本替换该组当前占位消息（按 groupId 定位）
    final newMsg = entry.versions[idx];
    final pos = _messages.indexWhere((m) => (m.groupId ?? m.id) == groupId);
    if (pos != -1) {
      _messages[pos] = newMsg;
    }
    _emitMessages();
    // 通知宿主持久化选中版本
    onSelectedVersionChanged?.call(groupId, idx);
  }

  @override
  Future<void> deleteMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final ids = messageIds.toSet();
    final before = _messages.length;
    _messages.removeWhere((m) => ids.contains(m.id));

    // 同步从版本分组中移除对应版本，清理空组并修正越界下标
    for (final e in _versionEntries) {
      e.versions.removeWhere((v) => ids.contains(v.id));
      if (e.versions.isNotEmpty &&
          e.selectedIndex >= e.versions.length) {
        e.selectedIndex = e.versions.length - 1;
      }
    }
    _versionEntries.removeWhere((e) => e.versions.isEmpty);
    _entryByGroup
      ..clear()
      ..addEntries(_versionEntries.map((e) => MapEntry(e.groupId, e)));

    if (_messages.length != before) _emitMessages();
  }

  @override
  Future<void> shareSelectedMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final ids = messageIds.toSet();
    final selected =
        _messages.where((m) => ids.contains(m.id)).toList(growable: false);
    if (selected.isEmpty) return;
    onShareMessages?.call(List.unmodifiable(selected));
  }

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
    // 通知宿主执行真实的重新生成（Hive + 流）
    onMessageAction?.call(
      _messages.firstWhere((m) => m.id == messageId),
      MessageAction.retry,
    );
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == messageId);
    if (_messages.length != before) {
      _emitMessages();
    }
    // 真实 Hive 删除由宿主通过 onMessageAction(delete) 持久化，此处只同步渲染层
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

  /// 全量同步：把现有 ChatMessage 列表整体重建为内部 _messages
  ///
  /// 用于会话初始加载、会话切换、以及任意结构性变更（编辑/删除/版本切换）。
  /// 幂等且会清空旧状态，因此调用方在切换会话时应重建本实例或先调用本方法。
  ///
  /// 兼容旧调用方：当传入的是**已折叠**消息（每分组一条）时，每组按单版本处理，
  /// 容器层不显示版本导航。需要多版本切换时，请改用 [syncConversationFull]
  /// 传入未折叠的全部消息。
  void syncFromMessages(List<hive.ChatMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages.map(_convertFromHive));
    // 折叠视图即最终视图：每条消息自成单版本分组
    _versionEntries
      ..clear()
      ..addAll(_messages.map((m) => _VersionEntry(
            groupId: m.groupId ?? m.id,
            versions: [m],
            selectedIndex: 0,
          )));
    _entryByGroup
      ..clear()
      ..addEntries(_versionEntries.map((e) => MapEntry(e.groupId, e)));
    _truncatePositionIndex = null;
    _emitMessages();
  }

  /// 全量同步会话（含全部版本 + 选中版本 + 截断位置）—— 供宿主集成阶段调用。
  ///
  /// 传入**未折叠**的全部消息，本数据源按 groupId 分组、按 version 升序，
  /// 并折叠为渲染视图（每分组取 [selectedVersions] 指定的版本，缺省取最新）。
  /// - [selectedVersions]：groupId -> 选中版本下标；
  /// - [truncateIndexRaw]：按原始消息数计的截断位置（与宿主 truncateIndex 语义一致）。
  void syncConversationFull(
    List<hive.ChatMessage> allMessages, {
    Map<String, int>? selectedVersions,
    int? truncateIndexRaw,
  }) {
    // 1. 全量转换为新模型
    final raw = allMessages.map(_convertFromHive).toList();

    // 2. 按 groupId 分组（保持首次出现顺序）
    final order = <String>[];
    final byGroup = <String, List<Message>>{};
    for (final m in raw) {
      final gid = m.groupId ?? m.id;
      byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <Message>[];
      }).add(m);
    }
    for (final list in byGroup.values) {
      list.sort((a, b) => a.version.compareTo(b.version));
    }

    // 3. 构建版本条目 + 折叠视图
    _versionEntries
      ..clear()
      ..addAll(order.map((gid) {
        final vers = byGroup[gid]!;
        final sel = selectedVersions?[gid];
        final idx = (sel != null && sel >= 0 && sel < vers.length)
            ? sel
            : vers.length - 1;
        return _VersionEntry(groupId: gid, versions: vers, selectedIndex: idx);
      }));
    _entryByGroup
      ..clear()
      ..addEntries(_versionEntries.map((e) => MapEntry(e.groupId, e)));

    _messages
      ..clear()
      ..addAll(_versionEntries.map((e) => e.versions[e.selectedIndex]));

    // 4. 映射截断位置（原始消息数 -> 折叠视图下标）
    _truncatePositionIndex = _mapTruncateToCollapsed(raw, truncateIndexRaw);

    _emitMessages();
  }

  /// 与宿主 home_page 一致的映射：原始 truncateIndex（消息条数）-> 折叠视图下标。
  ///
  /// 取原始列表前 [rawIndex] 条中首次出现的 groupId 去重计数，
  /// 分隔线落在该计数 - 1 的折叠下标（其上方即"已截断上下文"）。
  int? _mapTruncateToCollapsed(List<Message> raw, int? rawIndex) {
    if (rawIndex == null || rawIndex <= 0) return null;
    final seen = <String>{};
    final limit = rawIndex < raw.length ? rawIndex : raw.length;
    var count = 0;
    for (var i = 0; i < limit; i++) {
      final gid = raw[i].groupId ?? raw[i].id;
      if (seen.add(gid)) count++;
    }
    return count - 1;
  }

  /// 流式增量更新：把 contentDelta 追加到最后一个 TextPart，
  /// reasoningDelta 追加到 ThinkingPart。
  ///
  /// 由 home_page 的 SSE 流回调逐 chunk 调用，保证非经典样式下也能看到
  /// 逐字流式输出。找不到消息时静默忽略。
  void updateStreamingMessage(
    String messageId,
    String contentDelta, {
    String? reasoningDelta,
  }) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];
    final newParts = List<MessagePart>.from(msg.parts);
    var changed = false;

    // 推理增量 → 追加到最后一个 ThinkingPart
    if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
      final ti = newParts.lastIndexWhere((p) => p is ThinkingPart);
      if (ti != -1) {
        final t = newParts[ti] as ThinkingPart;
        newParts[ti] = ThinkingPart(
          id: t.id,
          content: t.content + reasoningDelta,
          tokenCount: t.tokenCount,
          duration: t.duration,
        );
      } else {
        newParts.insert(0, ThinkingPart(content: reasoningDelta));
      }
      changed = true;
    }

    // 正文增量 → 追加到最后一个 TextPart
    if (contentDelta.isNotEmpty) {
      final ti = newParts.lastIndexWhere((p) => p is TextPart);
      if (ti != -1) {
        final t = newParts[ti] as TextPart;
        newParts[ti] =
            TextPart(id: t.id, text: t.text + contentDelta, entities: t.entities);
      } else {
        newParts.add(TextPart(text: contentDelta));
      }
      changed = true;
    }

    if (!changed) return;
    _messages[index] = msg.copyWith(parts: newParts, isStreaming: true);
    _emitMessages();
  }

  /// 流式结束：标记该消息不再流式（样式渲染器据此关闭打字光标）
  void finishStreaming(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(isStreaming: false);
    _emitMessages();
  }

  /// 更新/插入工具调用状态（按 ToolCallPart.id 匹配）
  ///
  /// 新工具调用到达时 append 一个 pending/running 卡片；
  /// 工具结果返回时用同 id 的 completed 状态原地替换。
  void updateToolCall(String messageId, ToolCallPart toolCall) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];
    final newParts = List<MessagePart>.from(msg.parts);
    final ti =
        newParts.indexWhere((p) => p is ToolCallPart && p.id == toolCall.id);
    if (ti != -1) {
      newParts[ti] = toolCall;
    } else {
      newParts.add(toolCall);
    }
    _messages[index] = msg.copyWith(parts: newParts);
    _emitMessages();
  }

  @override
  void updateToolCallStatus(
    String messageId,
    String toolCallId,
    ToolCallStatus status, {
    dynamic result,
    String? errorMessage,
    Duration? duration,
    List<String>? recoverySuggestions,
  }) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];
    final newParts = List<MessagePart>.from(msg.parts);
    final ti = newParts.indexWhere(
        (p) => p is ToolCallPart && p.id == toolCallId);
    if (ti == -1) return;
    final old = newParts[ti] as ToolCallPart;
    newParts[ti] = old.copyWith(
      status: status,
      result: result ?? old.result,
      duration: duration ?? old.duration,
      errorMessage: errorMessage ?? old.errorMessage,
      recoverySuggestions: recoverySuggestions ?? old.recoverySuggestions,
    );
    _messages[index] = msg.copyWith(parts: newParts);
    _emitMessages();
  }

  @override
  void markMessageFailed(String messageId, String error) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(
      sendStatus: MessageSendStatus.failed,
    );
    // 失败原因以文本 part 追加，便于渲染层展示
    _emitMessages();
  }

  @override
  Future<void> retryFailedMessage(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(
      sendStatus: MessageSendStatus.sending,
    );
    _emitMessages();
    // 真实重发由宿主通过 onMessageAction(retry) 触发
    final msg = _messages[index];
    onMessageAction?.call(msg, MessageAction.retry);
  }

  @override
  Future<void> resumeGeneration() async {
    _state = _state.copyWith(isGenerating: true, currentPhase: '继续生成中...');
    _emitState();
  }

  /// 更新会话状态
  void updateState(ConversationState newState) {
    _state = newState;
    _emitState();
  }

  void _emitMessages() {
    // 流式/增量变更后，让各分组"当前选中版本"对象与折叠视图保持一致，
    // 保证版本切换时立即拿到最新内容（O(消息数)，典型量级可接受）。
    if (_versionEntries.isNotEmpty) {
      for (final m in _messages) {
        final entry = _entryByGroup[m.groupId ?? m.id];
        if (entry != null &&
            entry.selectedIndex >= 0 &&
            entry.selectedIndex < entry.versions.length) {
          entry.versions[entry.selectedIndex] = m;
        }
      }
    }
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

/// 内部版本分组条目（可变，供 Hive 实现维护）。
///
/// [versions] 元素引用会在流式增量时被 _emitMessages 刷新为折叠视图中的最新对象，
/// 因此版本切换可即时取到最新内容。
class _VersionEntry {
  final String groupId;
  final List<Message> versions;
  int selectedIndex;

  _VersionEntry({
    required this.groupId,
    required this.versions,
    required this.selectedIndex,
  });
}
