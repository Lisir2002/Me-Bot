// ignore_for_file: hardcoded_ui_string
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

/// Style 08：终端风格（Terminal）
///
/// 等宽字体、命令行风格、深色背景。
///   用户输入  `>`  青色
///   助手输出  `~`  绿色
///   工具调用  `$ tool --args` + spinner + 输出
///   连续工具  `$ tool_name ×3` 分组，展开后逐个显示命令与输出
///   思考      `# thinking...` 灰色注释行（流式自动展开，完成后折叠为一行摘要）
///   系统      `[system]` 黄色
///   错误      红色
///   流式光标  `▋` 块字符闪烁
///   引用回复  `> reply to msg-xxx: ...`
/// 不显示时间戳。
class TerminalRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.terminal;

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

  // 终端配色常量
  static const Color _bg = Color(0xFF1E1E1E);
  static const Color _green = Color(0xFF00FF00);
  static const Color _cyan = Color(0xFF00FFFF);
  static const Color _yellow = Color(0xFFFFFF00);
  static const Color _red = Color(0xFFFF5555);
  static const Color _gray = Color(0xFF888888);

  @override
  Widget build(BuildContext context) {
    _scrollCtrl ??= SmartScrollController()
      ..onUserScrolledAway = (away) => _showJump.value = away;
    return _TerminalView(
      scrollCtrl: _scrollCtrl!,
      showJump: _showJump,
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

class _TerminalView extends StatefulWidget {
  final SmartScrollController scrollCtrl;
  final ValueNotifier<bool> showJump;
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _TerminalView({
    required this.scrollCtrl,
    required this.showJump,
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
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
    return Container(
      color: TerminalRenderer._bg, // 整个渲染区域深色包裹
      child: StreamBuilder<List<Message>>(
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
              child: Text('\$ 等待输入…',
                  style: TextStyle(
                      color: TerminalRenderer._green,
                      fontFamily: 'monospace',
                      fontSize: 14)),
            );
          }
          return Stack(
            children: [
              ListView.builder(
                controller: widget.scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final w = _buildMessage(context, messages[index], messages);
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
      ),
    );
  }

  /// 统一包裹：消息容器语义 label（用户/助手+时间）+ 长按弹出统一菜单
  Widget _buildMessage(
      BuildContext context, Message message, List<Message> allMessages) {
    final body = _buildMessageBody(context, message, allMessages);
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

  Widget _buildMessageBody(
      BuildContext context, Message message, List<Message> allMessages) {
    switch (message.role) {
      case MessageRole.user:
        return _buildUserMessage(message, allMessages);
      case MessageRole.system:
        return _TerminalLine(
          prefix: '[system] ',
          prefixColor: TerminalRenderer._yellow,
          text: message.textContent,
          textColor: TerminalRenderer._yellow,
        );
      case MessageRole.tool:
      case MessageRole.assistant:
        return _buildAssistantMessage(message);
    }
  }

  /// 用户消息：终端输入行 `> user input`
  ///
  /// 有 referencedMessageId 时在上方显示 `> reply to msg-xxx: ...`
  Widget _buildUserMessage(Message message, List<Message> allMessages) {
    final children = <Widget>[];

    // 引用回复：查找被引用消息内容
    if (message.referencedMessageId != null) {
      Message? refMsg;
      for (final m in allMessages) {
        if (m.id == message.referencedMessageId) {
          refMsg = m;
          break;
        }
      }
      if (refMsg != null) {
        final preview = refMsg.textContent;
        final truncated = preview.length > 50
            ? '${preview.substring(0, 50)}…'
            : preview;
        children.add(_TerminalLine(
          prefix: '> reply to ${message.referencedMessageId}: ',
          prefixColor: TerminalRenderer._gray,
          text: truncated,
          textColor: TerminalRenderer._gray,
        ));
      }
    }

    children.add(_TerminalLine(
      prefix: '> ',
      prefixColor: TerminalRenderer._cyan,
      text: message.textContent,
      textColor: TerminalRenderer._cyan,
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// 助手/工具消息：按 part 渲染，连续工具调用分组
  Widget _buildAssistantMessage(Message message) {
    final parts = message.parts;
    final groups = groupConsecutiveToolCalls(parts);
    var groupIdx = 0;
    final children = <Widget>[];
    final isStreaming = message.isStreaming;
    int? lastTextIndex;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];

      // 命中工具组：终端风格分组显示 `$ tool_name ×N`
      if (groupIdx < groups.length &&
          identical(part, groups[groupIdx].toolCalls.first)) {
        final group = groups[groupIdx];
        children.add(_TerminalToolGroup(toolCalls: group.toolCalls));
        i += group.toolCalls.length - 1;
        groupIdx++;
        continue;
      }

      switch (part) {
        case TextPart():
          children.add(_TerminalLine(
            prefix: '~ ',
            prefixColor: TerminalRenderer._green,
            text: part.text,
            textColor: TerminalRenderer._green,
          ));
          lastTextIndex = children.length - 1;
        case ThinkingPart():
          // 终端风格思考：`# thinking...` 灰色注释行
          children.add(_TerminalThinkingBlock(
            part: part,
            isStreaming: isStreaming,
          ));
        case ToolCallPart():
          children.add(_TerminalToolBlock(part: part));
        case CodePart():
          children.add(_TerminalCodeBlock(part: part));
        case ApprovalPart():
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => widget.dataSource.approveAction(part.id),
            onReject: () => widget.dataSource.rejectAction(part.id),
          ));
        default:
          // 图片/文件/产物等用共享组件兜底
          children.add(MessagePartRenderer(
            part: part,
            uiState: _uiState,
            onUIStateChanged: _update,
          ));
      }
    }

    // 流式中：在最后一个文本行后追加块字符光标
    if (isStreaming && lastTextIndex != null) {
      children.insert(
        lastTextIndex + 1,
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 2),
          child: _TerminalBlockCursor(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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

/// 普通终端文本行：前缀 + 内容
class _TerminalLine extends StatelessWidget {
  final String prefix;
  final Color prefixColor;
  final String text;
  final Color textColor;

  const _TerminalLine({
    required this.prefix,
    required this.prefixColor,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 13, height: 1.5),
          children: [
            TextSpan(text: prefix, style: TextStyle(color: prefixColor)),
            TextSpan(text: text, style: TextStyle(color: textColor)),
          ],
        ),
      ),
    );
  }
}

/// 工具调用分组：终端风格 `$ tool_name ×N`
///
/// 折叠态：`$ tool_name ×N` + 状态指示（绿勾 / 红叉 / 运行中）
/// 展开态：逐个列出每个命令及其输出
/// 自动行为：有运行中工具自动展开，全部完成后自动折叠（与 ToolGroupCard 逻辑一致）
class _TerminalToolGroup extends StatefulWidget {
  final List<ToolCallPart> toolCalls;
  const _TerminalToolGroup({required this.toolCalls});

  @override
  State<_TerminalToolGroup> createState() => _TerminalToolGroupState();
}

class _TerminalToolGroupState extends State<_TerminalToolGroup> {
  bool _userToggled = false;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = _shouldAutoExpand();
  }

  @override
  void didUpdateWidget(_TerminalToolGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userToggled) {
      _expanded = _shouldAutoExpand();
    }
  }

  bool _shouldAutoExpand() => widget.toolCalls.any((t) =>
      t.status == ToolCallStatus.running || t.status == ToolCallStatus.pending);

  bool get _hasError =>
      widget.toolCalls.any((t) => t.status == ToolCallStatus.error);

  bool get _hasRunning => widget.toolCalls.any((t) =>
      t.status == ToolCallStatus.running || t.status == ToolCallStatus.pending);

  void _handleTap() {
    setState(() {
      _userToggled = true;
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final toolName =
        widget.toolCalls.isEmpty ? 'tool' : widget.toolCalls.first.toolName;
    final count = widget.toolCalls.length;

    // 状态符号：成功 `✓` 绿色 / 失败 `✗` 红色 / 运行中 `…` 绿色
    final String statusSymbol;
    final Color statusColor;
    if (_hasError) {
      statusSymbol = '✗';
      statusColor = TerminalRenderer._red;
    } else if (_hasRunning) {
      statusSymbol = '…';
      statusColor = TerminalRenderer._green;
    } else {
      statusSymbol = '✓';
      statusColor = TerminalRenderer._green;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组头部：`$ tool_name ×N   [状态]`
        InkWell(
          onTap: _handleTap,
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13, height: 1.5),
              children: [
                const TextSpan(
                    text: '\$ ',
                    style: TextStyle(color: TerminalRenderer._green)),
                TextSpan(
                    text: '$toolName ×$count',
                    style: const TextStyle(color: Colors.white)),
                TextSpan(
                    text: '   $statusSymbol',
                    style: TextStyle(color: statusColor)),
                TextSpan(
                    text: _expanded ? '  ▾' : '  ▸',
                    style: const TextStyle(color: TerminalRenderer._gray)),
              ],
            ),
          ),
        ),
        // 展开后逐个显示命令与输出
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  widget.toolCalls.map((t) => _TerminalToolBlock(part: t)).toList(),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 工具调用：命令执行样式 `$ tool_name --args` + spinner + 输出
class _TerminalToolBlock extends StatelessWidget {
  final ToolCallPart part;
  const _TerminalToolBlock({required this.part});

  @override
  Widget build(BuildContext context) {
    final argStr = part.arguments.entries
        .map((e) => '--${e.key}=${e.value}')
        .join(' ');
    final isRunning = part.status == ToolCallStatus.running;
    final isError = part.status == ToolCallStatus.error;

    final outColor = isError ? TerminalRenderer._red : TerminalRenderer._gray;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 命令行
        RichText(
          text: TextSpan(
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 13, height: 1.5),
            children: [
              const TextSpan(
                  text: '\$ ', style: TextStyle(color: TerminalRenderer._green)),
              TextSpan(
                  text: '${part.toolName} $argStr'.trimRight(),
                  style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        // 执行中 spinner
        if (isRunning)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 2),
            child: _TerminalSpinner(color: TerminalRenderer._green),
          ),
        // 结果输出
        if (part.result != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              part.result.toString(),
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: outColor),
            ),
          ),
        // 错误
        if (isError && part.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              'ERR: ${part.errorMessage}',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: TerminalRenderer._red),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 终端思考块：`# thinking...` 灰色注释行
///
/// 与增强 ThinkingPartRenderer 逻辑一致：
/// - 流式中（isStreaming=true）：自动展开，显示 `# thinking...` + 脉冲点 + 正文
/// - 完成后：自动折叠为一行 `# thinking` + 摘要（前30字）
/// - 保留手动点击切换
class _TerminalThinkingBlock extends StatefulWidget {
  final ThinkingPart part;
  final bool isStreaming;
  const _TerminalThinkingBlock({
    required this.part,
    required this.isStreaming,
  });

  @override
  State<_TerminalThinkingBlock> createState() => _TerminalThinkingBlockState();
}

class _TerminalThinkingBlockState extends State<_TerminalThinkingBlock> {
  bool _userToggled = false;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isStreaming;
  }

  @override
  void didUpdateWidget(_TerminalThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userToggled) {
      _expanded = widget.isStreaming;
    }
  }

  void _handleTap() {
    setState(() {
      _userToggled = true;
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.part.content.trim();
    final preview =
        summary.length > 30 ? '${summary.substring(0, 30)}…' : summary;
    final gray = TerminalRenderer._gray;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _handleTap,
          child: Row(
            children: [
              // 流式中脉冲点，完成后静态 `#` 符号
              if (widget.isStreaming)
                const _TerminalPulseDot(color: TerminalRenderer._gray, size: 8)
              else
                const Text('#',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: TerminalRenderer._gray)),
              const SizedBox(width: 6),
              Text(
                widget.isStreaming ? 'thinking...' : 'thinking',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: TerminalRenderer._gray),
              ),
              // 折叠态右侧显示摘要
              if (!_expanded && preview.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(preview,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: TerminalRenderer._gray)),
              ],
            ],
          ),
        ),
        // 展开后显示思考正文
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text(
              widget.part.content,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: gray),
            ),
          ),
        const SizedBox(height: 2),
      ],
    );
  }
}

/// 终端脉冲点 —— 透明度 0.3↔1 循环
class _TerminalPulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const _TerminalPulseDot({required this.color, required this.size});

  @override
  State<_TerminalPulseDot> createState() => _TerminalPulseDotState();
}

class _TerminalPulseDotState extends State<_TerminalPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Opacity(
          opacity: 0.3 + 0.7 * _c.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

/// 终端流式块字符光标 `▋` 闪烁
class _TerminalBlockCursor extends StatefulWidget {
  const _TerminalBlockCursor();

  @override
  State<_TerminalBlockCursor> createState() => _TerminalBlockCursorState();
}

class _TerminalBlockCursorState extends State<_TerminalBlockCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Opacity(
          opacity: _c.value,
          child: Container(
            width: 8,
            height: 15,
            color: TerminalRenderer._green,
          ),
        );
      },
    );
  }
}

/// 终端 spinner：动画省略号
class _TerminalSpinner extends StatefulWidget {
  final Color color;
  const _TerminalSpinner({required this.color});

  @override
  State<_TerminalSpinner> createState() => _TerminalSpinnerState();
}

class _TerminalSpinnerState extends State<_TerminalSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dots = ['.', '..', '...'];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final d = dots[(_c.value * dots.length).floor() % dots.length];
        return Text('running$d',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 12, color: widget.color));
      },
    );
  }
}

/// 终端代码块：深色背景 + 等宽字体，简单渲染
class _TerminalCodeBlock extends StatelessWidget {
  final CodePart part;
  const _TerminalCodeBlock({required this.part});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('  ${part.filename ?? part.language}',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: TerminalRenderer._cyan)),
          const SizedBox(height: 4),
          Text(part.code,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: TerminalRenderer._green)),
        ],
      ),
    );
  }
}
