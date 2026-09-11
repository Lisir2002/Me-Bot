import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/message_animations.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 01: 经典气泡式渲染器
///
/// 布局特点：
/// - 用户消息右对齐，助手左对齐，圆角气泡
/// - 头像显示（用户 Icons.person，助手 Icons.smart_toy）
/// - 时间戳显示在气泡下方，小字
/// - 连续工具调用聚合为 ToolGroupCard（置于气泡内）
/// - 思考过程接入流式状态（isStreaming），流式中自动展开
/// - 用户消息带引用时，气泡顶部渲染 QuoteRefWidget
/// - 流式助手消息在最后一个文本后附加 StreamingCursor
/// - 气泡间距：同角色连续消息 4px，不同角色 12px
/// - 气泡最大宽度不超过屏幕宽度的 75%
///
/// 适用场景：日常聊天、短对话、通用场景
class ClassicBubbleRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.classicBubble;

  /// 智能滚动控制器（懒初始化，随渲染器生命周期释放）
  SmartScrollController? _scrollCtrl;
  /// 是否显示"跳转到底部"按钮
  final ValueNotifier<bool> _showJump = ValueNotifier<bool>(false);

  @override
  void onDetach() {
    _scrollCtrl?.dispose();
    _scrollCtrl = null;
    super.onDetach();
  }

  @override
  Widget build(BuildContext context) {
    _scrollCtrl ??= SmartScrollController()
      ..onUserScrolledAway = (away) => _showJump.value = away;
    final ctrl = _scrollCtrl!;
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        // 新消息到达且用户在底部附近时，自动平滑跟随到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctrl.hasClients && ctrl.shouldAutoScroll) {
            ctrl.animateTo(
              ctrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        return Stack(
          children: [
            ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final w = _buildMessage(context, messages, index);
                // 仅最新一条消息播放底部滑入 + 淡入
                final isLast = index == messages.length - 1;
                return isLast ? MessageSlideIn(child: w) : w;
              },
            ),
            // 上翻后显示"跳转到底部"悬浮按钮
            Positioned(
              right: 12,
              bottom: 12,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showJump,
                builder: (context, show, _) => show
                    ? FloatingActionButton.small(
                        onPressed: ctrl.smartJumpToBottom,
                        child: const Icon(Icons.keyboard_arrow_down),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建单条消息行（头像 + 气泡 + 时间戳）
  ///
  /// [messages] 用于与上一条比较角色以决定气泡间距，
  /// 同时用于根据 referencedMessageId 查找被引用消息预览。
  Widget _buildMessage(
      BuildContext context, List<Message> messages, int index) {
    final message = messages[index];
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.75;

    // 气泡间距：同角色连续消息 4px，不同角色 12px
    double bottomGap = 12;
    if (index > 0 && messages[index - 1].role == message.role) {
      bottomGap = 4;
    }

    // 用户消息引用回复预览（气泡顶部）
    final quoteRef = _buildQuoteRef(context, messages, message);

    final row = Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 助手头像在左侧
          if (!isUser) _buildAvatar(context, isUser),
          if (!isUser) const SizedBox(width: 8),
          // 气泡主体（受限最大宽度）
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 气泡内容
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isUser
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                      bottomRight: isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 引用回复组件（如存在）
                      if (quoteRef != null) quoteRef,
                      _buildParts(context, message, isUser),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 时间戳（气泡下方小字）
                Text(
                  _formatTime(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // 用户头像在右侧
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildAvatar(context, isUser),
        ],
      ),
    );

    // 长按弹出统一上下文菜单（复制/引用/重新生成/分享/删除）
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showContextMenu(context, message),
      child: row,
    );

    final timeStr = _formatTime(message.timestamp);
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: isUser
          ? l10n.convStyleUserMessageSemantic(timeStr)
          : l10n.convStyleAssistantMessageSemantic(timeStr),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          // 用户消息发送失败：错误提示 + 重试按钮
          if (isUser && message.sendStatus == MessageSendStatus.failed)
            _buildFailedBar(context, message),
        ],
      ),
    );
  }

  /// 发送失败条：错误图标 + 重试按钮
  Widget _buildFailedBar(BuildContext context, Message message) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Text(l10n.convStyleSendFailed,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => dataSource.retryFailedMessage(message.id),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  /// 弹出长按上下文菜单；复制自包含，其余动作经 dataSource 回调交宿主处理
  void _showContextMenu(BuildContext context, Message message) {
    final text = message.textContent;
    final l10n = context.l10n;
    showMessageContextMenu(
      context,
      message,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: text));
        showAppSnackBar(
          context,
          message: l10n.convStyleCopied,
          type: NotificationType.success,
        );
      },
      onQuote: () =>
          dataSource.onMessageAction?.call(message, MessageAction.quote),
      onRetry: () =>
          dataSource.onMessageAction?.call(message, MessageAction.retry),
      onShare: () =>
          dataSource.onMessageAction?.call(message, MessageAction.share),
      onDelete: () async {
        await dataSource.deleteMessage(message.id);
        if (context.mounted) {
          showAppSnackBar(
            context,
            message: l10n.convStyleDeleted,
            type: NotificationType.success,
          );
        }
      },
    );
  }

  /// 构建用户消息的引用回复组件
  ///
  /// 从消息列表中根据 referencedMessageId 查找被引用消息，
  /// 取其 textContent 作为预览（QuoteRefWidget 内部截断为 50 字）。
  Widget? _buildQuoteRef(
      BuildContext context, List<Message> messages, Message message) {
    final refId = message.referencedMessageId;
    if (refId == null) return null;

    Message? ref;
    for (final m in messages) {
      if (m.id == refId) {
        ref = m;
        break;
      }
    }
    if (ref == null) return null;

    final preview = ref.textContent.trim();
    if (preview.isEmpty) return null;

    final senderName = ref.assistantName ??
        (ref.role == MessageRole.user
            ? context.l10n.convStyleSenderYou
            : context.l10n.convStyleSenderAssistant);
    return QuoteRefWidget(
      senderName: senderName,
      contentPreview: preview,
      timestamp: ref.timestamp,
    );
  }

  /// 构建头像
  Widget _buildAvatar(BuildContext context, bool isUser) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.secondaryContainer,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 18,
        color: isUser
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSecondaryContainer,
      ),
    );
  }

  /// 构建消息内部的所有 part
  ///
  /// 连续 ToolCallPart 会聚合为一个 ToolGroupCard；
  /// 流式中的助手消息在最后一个 TextPart 后附加 StreamingCursor。
  Widget _buildParts(BuildContext context, Message message, bool isUser) {
    final children = <Widget>[];

    // 最后一个 TextPart 的下标（用于在其后附加流式光标）
    var lastTextIndex = -1;
    for (var i = 0; i < message.parts.length; i++) {
      if (message.parts[i] is TextPart) lastTextIndex = i;
    }

    // 连续工具调用聚合缓冲
    final pendingTools = <ToolCallPart>[];
    void flushTools() {
      if (pendingTools.isNotEmpty) {
        // 聚合卡片按整体状态加微动画（running 脉冲 / success 弹出 / error 抖动）
        final overall = pendingTools.any((t) => t.status == ToolCallStatus.error)
            ? ToolCallStatus.error
            : pendingTools.any((t) => t.status == ToolCallStatus.running)
                ? ToolCallStatus.running
                : ToolCallStatus.success;
        children.add(ToolCallStatusAnimation(
          status: overall,
          child: ToolGroupCard(
            toolCalls: List.of(pendingTools),
            uiState: uiState,
            onUIStateChanged: updateUIState,
          ),
        ));
        pendingTools.clear();
      }
    }

    for (var i = 0; i < message.parts.length; i++) {
      final part = message.parts[i];
      switch (part) {
        case TextPart():
          flushTools();
          children.add(_buildTextPart(context, part));
          // 流式中的助手消息：最后一个 TextPart 后附加光标
          if (message.isStreaming && !isUser && i == lastTextIndex) {
            children.add(const StreamingCursor());
          }
        case CodePart():
          flushTools();
          children.add(CodePartRenderer(part: part));
        case ToolCallPart():
          // 累积连续工具调用，稍后聚合为 ToolGroupCard
          pendingTools.add(part);
        case ThinkingPart():
          flushTools();
          final isCollapsed =
              uiState.collapsedThinkingIds.contains(part.id);
          children.add(ThinkingExpandAnimation(
            expanded: !isCollapsed,
            child: ThinkingPartRenderer(
              part: part,
              collapsed: isCollapsed,
              // 传入流式状态：流式中自动展开 + 脉冲点
              isStreaming: message.isStreaming,
              onToggleCollapse: () => updateUIState(
                uiState.toggleThinking(part.id),
              ),
            ),
          ));
        case ApprovalPart():
          flushTools();
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          flushTools();
          children.add(ImagePartRenderer(part: part));
        case FilePart():
          flushTools();
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          flushTools();
          children.add(ArtifactPartRenderer(part: part));
        case TaskPart():
          flushTools();
          children.add(Text('📋 ${part.title}'));
      }
    }
    flushTools();

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// 构建文本部分
  Widget _buildTextPart(BuildContext context, TextPart part) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    // 长文本懒渲染：超过 500 字默认折叠，显示"展开全文"
    return SelectionArea(
      child: part.text.length > 500
          ? _LazyLongText(text: part.text, style: style)
          : Text(part.text, style: style),
    );
  }

  /// 格式化时间戳
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 长文本懒渲染：默认只显示前 300 字符 + "展开全文"按钮
class _LazyLongText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const _LazyLongText({required this.text, this.style});

  @override
  State<_LazyLongText> createState() => _LazyLongTextState();
}

class _LazyLongTextState extends State<_LazyLongText> {
  static const int _previewLen = 300;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final shown = _expanded || widget.text.length <= _previewLen
        ? widget.text
        : '${widget.text.substring(0, _previewLen)}…';
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shown, style: widget.style),
        if (!_expanded && widget.text.length > _previewLen)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.convStyleExpandFullTextWithCount(widget.text.length),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
