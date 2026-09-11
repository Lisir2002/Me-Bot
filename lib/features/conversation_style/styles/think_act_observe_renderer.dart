import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/build_context_l10n.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/message_animations.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 07：思考-行动-观察闭环（Think-Act-Observe）
///
/// 左侧 rail 时间线，三阶段明确区分：
///   思考 Think  —— 紫色 Icons.psychology
///   行动 Act    —— 蓝色 Icons.build
///   观察 Observe—— 绿色 Icons.visibility
/// 将每条助手消息的 parts 按类型分组到三个阶段，文本回答作为最终结论显示在闭环之后。
class ThinkActObserveRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.thinkActObserve;

  /// 智能滚动控制器（懒初始化，随渲染器 onDetach 释放）
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
    return _TaoView(
      scrollCtrl: _scrollCtrl!,
      showJump: _showJump,
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

class _TaoView extends StatefulWidget {
  final SmartScrollController scrollCtrl;
  final ValueNotifier<bool> showJump;
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _TaoView({
    required this.scrollCtrl,
    required this.showJump,
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_TaoView> createState() => _TaoViewState();
}

class _TaoViewState extends State<_TaoView> {
  late ConversationUIState _uiState;

  @override
  void initState() {
    super.initState();
    _uiState = widget.initialUiState;
  }

  void _update(ConversationUIState s) {
    setState(() => _uiState = s);
    widget.onUIStateChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: widget.dataSource.messageStream,
      initialData: widget.dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        // 新消息到达且用户在底部附近时，自动平滑跟随到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctrl = widget.scrollCtrl;
          if (ctrl.hasClients && ctrl.shouldAutoScroll) {
            ctrl.animateTo(
              ctrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        if (messages.isEmpty) {
          return const Center(
            // ignore: hardcoded_ui_string —— 空态暂无 l10n 键，保留原文案
            child: Text('暂无消息'),
          );
        }
        return Stack(
          children: [
            ListView.builder(
              controller: widget.scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final w = _buildMessage(context, messages[index]);
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
                valueListenable: widget.showJump,
                builder: (context, show, _) => show
                    ? FloatingActionButton.small(
                        onPressed: widget.scrollCtrl.smartJumpToBottom,
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

  /// 统一包裹：消息容器语义 label（用户/助手+时间）+ 长按弹出统一菜单
  Widget _buildMessage(BuildContext context, Message message) {
    final body = _buildMessageBody(context, message);
    final timeStr = _formatTime(message.timestamp);
    final l10n = context.l10n;
    final String? label = switch (message.role) {
      MessageRole.user => l10n.convStyleUserMessageSemantic(timeStr),
      MessageRole.assistant => l10n.convStyleAssistantMessageSemantic(timeStr),
      _ => null,
    };
    return Semantics(
      container: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showContextMenu(context, message),
        child: body,
      ),
    );
  }

  Widget _buildMessageBody(BuildContext context, Message message) {
    if (message.role == MessageRole.user) {
      return _UserRow(
        message: message,
        onQuoteTap: message.referencedMessageId != null ? () {} : null,
      );
    }
    if (message.role == MessageRole.system) {
      return _SystemRow(text: message.textContent);
    }

    final isStreaming = message.isStreaming;

    // 按类型把 parts 分组到三阶段
    final think = message.parts.whereType<ThinkingPart>().toList();
    // 行动阶段：使用 groupConsecutiveToolCalls 聚合连续工具调用
    final toolGroups = groupConsecutiveToolCalls(message.parts);
    final approvals =
        message.parts.whereType<ApprovalPart>().toList();
    // 观察阶段：从已完成的工具结果派生结果分析
    final observeResults = message.parts
        .whereType<ToolCallPart>()
        .where((t) => t.result != null)
        .toList();
    // 最终结论：文本与代码等非闭环内容
    final conclusion = message.parts
        .where((p) =>
            p is TextPart || p is CodePart || p is ImagePart || p is FilePart || p is ArtifactPart)
        .toList();

    final stages = <Widget>[];

    if (think.isNotEmpty) {
      stages.add(_StageRail(
        color: const Color(0xFF8E44AD),
        icon: Icons.psychology,
        // ignore: hardcoded_ui_string —— 三阶段设计规范标签（中英混排）暂无 l10n 键，保留原文案
        label: '思考 Think',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: think
              .map((t) => ThinkingPartRenderer(
                    part: t,
                    collapsed: _uiState.collapsedThinkingIds.contains(t.id),
                    onToggleCollapse: () => _update(_uiState.toggleThinking(t.id)),
                    isStreaming: isStreaming,
                  ))
              .toList(),
        ),
      ));
    }

    if (toolGroups.isNotEmpty || approvals.isNotEmpty) {
      final actChildren = <Widget>[];
      // 工具组聚合
      for (final group in toolGroups) {
        actChildren.add(ToolGroupCard(
          toolCalls: group.toolCalls,
          uiState: _uiState,
          onUIStateChanged: _update,
        ));
      }
      // 审批部分
      for (final approval in approvals) {
        actChildren.add(ApprovalPartRenderer(
          part: approval,
          onApprove: () => widget.dataSource.approveAction(approval.id),
          onReject: () => widget.dataSource.rejectAction(approval.id),
        ));
      }
      stages.add(_StageRail(
        color: Colors.blue,
        icon: Icons.build,
        // ignore: hardcoded_ui_string —— 三阶段设计规范标签（中英混排）暂无 l10n 键，保留原文案
        label: '行动 Act',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actChildren,
        ),
      ));
    }

    if (observeResults.isNotEmpty) {
      stages.add(_StageRail(
        color: Colors.green,
        icon: Icons.visibility,
        // ignore: hardcoded_ui_string —— 三阶段设计规范标签（中英混排）暂无 l10n 键，保留原文案
        label: '观察 Observe',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: observeResults.map((t) => _ObserveCard(part: t)).toList(),
        ),
      ));
    }

    // 三阶段闭环后：最终结论
    if (conclusion.isNotEmpty) {
      stages.add(Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...conclusion
                .map((p) => MessagePartRenderer(
                      part: p,
                      uiState: _uiState,
                      onUIStateChanged: _update,
                    )),
            // 流式光标
            if (isStreaming) const StreamingCursor(),
          ],
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: stages,
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
          widget.dataSource.onMessageAction?.call(message, MessageAction.quote),
      onRetry: () =>
          widget.dataSource.onMessageAction?.call(message, MessageAction.retry),
      onShare: () =>
          widget.dataSource.onMessageAction?.call(message, MessageAction.share),
      onDelete: () async {
        await widget.dataSource.deleteMessage(message.id);
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

  /// 格式化时间戳（语义 label 用）
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 三阶段 rail 行：圆形图标节点 + 4px 彩色连接线 + 内容
class _StageRail extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Widget content;

  const _StageRail({
    required this.color,
    required this.icon,
    required this.label,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4px 宽彩色 rail + 圆形图标节点
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              Expanded(
                child: Container(width: 4, color: color.withValues(alpha: 0.4)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 观察阶段结果卡片：结果摘要 + 质量评分（如果有）
class _ObserveCard extends StatelessWidget {
  final ToolCallPart part;
  const _ObserveCard({required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 尝试从结果中提取质量评分
    double? score;
    if (part.result is Map) {
      final m = part.result as Map;
      final raw = m['qualityScore'] ?? m['score'] ?? m['rating'];
      if (raw is num) score = raw.toDouble();
    }
    final summary = part.result.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(
                // ignore: hardcoded_ui_string —— 观察阶段结果标题暂无 l10n 键，保留原文案
                child: Text('结果分析 · ${part.toolName}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // ignore: hardcoded_ui_string —— 质量评分标签暂无 l10n 键，保留原文案
                  child: Text('评分 ${score.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary.length > 300 ? '${summary.substring(0, 300)}…' : summary,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Message message;
  final VoidCallback? onQuoteTap;
  const _UserRow({required this.message, this.onQuoteTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 引用回复
            if (message.referencedMessageId != null)
              QuoteRefWidget(
                senderName: message.assistantName ?? context.l10n.convStyleSenderAssistant,
                contentPreview: message.textContent,
                timestamp: message.timestamp,
                onTap: onQuoteTap,
              ),
            Text(message.textContent,
                style: TextStyle(color: theme.colorScheme.onPrimary)),
          ],
        ),
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  final String text;
  const _SystemRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      child: Text('[system] $text',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic)),
    );
  }
}
