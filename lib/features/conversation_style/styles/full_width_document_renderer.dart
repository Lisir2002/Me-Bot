import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/message_animations.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 02: 全宽文档式渲染器
///
/// 布局特点：
/// - 消息占满宽度，无气泡边框，用 Divider 分隔线区分消息
/// - 不显示头像，用角色标签（"用户"/"助手"）代替
/// - 不显示时间戳
/// - 连续工具调用聚合为全宽 ToolGroupCard
/// - 思考过程接入流式状态（isStreaming）
/// - 用户消息带引用时渲染 QuoteRefWidget
/// - 流式助手消息在最后一个文本后附加 StreamingCursor
/// - 排版节奏：段间距 8px，代码块前后 12px
/// - 用户消息用引用块样式（左边框 + 斜体）区分
///
/// 适用场景：长文本、代码密集、文档生成
class FullWidthDocumentRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.fullWidthDocument;

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
            ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              itemCount: messages.length,
              separatorBuilder: (context, index) => const Divider(height: 32),
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

  /// 构建单条消息 —— 全宽布局，角色标签 + 内容
  Widget _buildMessage(
      BuildContext context, List<Message> messages, int index) {
    final message = messages[index];
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // 用户消息引用回复预览
    final quoteRef = _buildQuoteRef(context, messages, message);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 角色标签行
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isUser ? l10n.convStyleSenderYou : l10n.convStyleSenderAssistant,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isUser
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (message.modelId != null) ...[
              const SizedBox(width: 8),
              Text(
                message.modelId!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // 引用回复组件（如存在）
        if (quoteRef != null) quoteRef,
        if (quoteRef != null) const SizedBox(height: 8),
        // 消息内容
        _buildParts(context, message, isUser),
      ],
    );

    // 长按弹出统一上下文菜单（复制/引用/重新生成/分享/删除）
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showContextMenu(context, message),
      child: body,
    );

    final timeStr = _formatTime(message.timestamp);
    return Semantics(
      container: true,
      label: isUser
          ? l10n.convStyleUserMessageSemantic(timeStr)
          : l10n.convStyleAssistantMessageSemantic(timeStr),
      child: tappable,
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

  /// 格式化时间戳（用于语义标签）
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 构建用户消息的引用回复组件
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

  /// 构建消息内部的所有 part
  ///
  /// 连续 ToolCallPart 聚合为 ToolGroupCard；
  /// 流式助手消息在最后一个 TextPart 后附加 StreamingCursor；
  /// 排版节奏：文本段落间 8px，代码块前后 12px。
  Widget _buildParts(BuildContext context, Message message, bool isUser) {
    final children = <Widget>[];

    // 最后一个 TextPart 的下标（用于在其后附加流式光标）
    var lastTextIndex = -1;
    for (var i = 0; i < message.parts.length; i++) {
      if (message.parts[i] is TextPart) lastTextIndex = i;
    }

    // 上一个内容的类型，用于计算间距
    String? prevKind;

    /// 按排版节奏把 [child] 加入 children
    void addChild(Widget child, String kind) {
      if (children.isNotEmpty) {
        double gap;
        if (kind == 'code' || prevKind == 'code') {
          gap = 12; // 代码块前后 12px
        } else if (kind == 'text' && prevKind == 'text') {
          gap = 8; // 文本段落间距 8px
        } else {
          gap = 8; // 其他元素之间默认 8px
        }
        children.add(SizedBox(height: gap));
      }
      children.add(child);
      prevKind = kind;
    }

    // 连续工具调用聚合缓冲
    final pendingTools = <ToolCallPart>[];
    void flushTools() {
      if (pendingTools.isNotEmpty) {
        addChild(
          ToolGroupCard(
            toolCalls: List.of(pendingTools),
            uiState: uiState,
            onUIStateChanged: updateUIState,
          ),
          'tool',
        );
        pendingTools.clear();
      }
    }

    for (var i = 0; i < message.parts.length; i++) {
      final part = message.parts[i];
      switch (part) {
        case TextPart():
          flushTools();
          // 用户消息用引用块样式，助手消息用大行距正文
          if (isUser) {
            addChild(_buildQuoteText(context, part), 'text');
          } else {
            addChild(
              TextPartRenderer(
                part: part,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.8,
                    ),
              ),
              'text',
            );
          }
          // 流式助手消息：最后一个 TextPart 后附加光标（紧跟文本，不另起间距行）
          if (message.isStreaming && !isUser && i == lastTextIndex) {
            children.add(const StreamingCursor());
          }
        case CodePart():
          flushTools();
          // 代码块显示运行按钮
          addChild(
            CodePartRenderer(part: part, showRunButton: true),
            'code',
          );
        case ToolCallPart():
          // 累积连续工具调用，稍后聚合为 ToolGroupCard
          pendingTools.add(part);
        case ThinkingPart():
          flushTools();
          final isCollapsed =
              uiState.collapsedThinkingIds.contains(part.id);
          addChild(
            ThinkingPartRenderer(
              part: part,
              collapsed: isCollapsed,
              // 传入流式状态：流式中自动展开 + 脉冲点
              isStreaming: message.isStreaming,
              onToggleCollapse: () => updateUIState(
                uiState.toggleThinking(part.id),
              ),
            ),
            'think',
          );
        case ApprovalPart():
          flushTools();
          addChild(
            ApprovalPartRenderer(
              part: part,
              onApprove: () => dataSource.approveAction(part.id),
              onReject: () => dataSource.rejectAction(part.id),
            ),
            'other',
          );
        case ImagePart():
          flushTools();
          addChild(ImagePartRenderer(part: part), 'other');
        case FilePart():
          flushTools();
          addChild(FilePartRenderer(part: part), 'other');
        case ArtifactPart():
          flushTools();
          addChild(ArtifactPartRenderer(part: part), 'other');
        case TaskPart():
          flushTools();
          addChild(Text('📋 ${part.title}'), 'other');
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

  /// 用户消息引用块样式 —— 左边框 + 斜体
  Widget _buildQuoteText(BuildContext context, TextPart part) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: SelectionArea(
        child: Text(
          part.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.8,
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
