// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';

import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 08：终端风格（Terminal）
///
/// 等宽字体、命令行风格、深色背景。
///   用户输入  `>`  青色
///   助手输出  `~`  绿色
///   工具调用  `$ tool --args` + spinner + 输出
///   思考      `[thinking]` 灰色
///   系统      `[system]` 黄色
///   错误      红色
/// 不显示时间戳。
class TerminalRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.terminal;

  // 终端配色常量
  static const Color _bg = Color(0xFF1E1E1E);
  static const Color _green = Color(0xFF00FF00);
  static const Color _cyan = Color(0xFF00FFFF);
  static const Color _yellow = Color(0xFFFFFF00);
  static const Color _red = Color(0xFFFF5555);
  static const Color _gray = Color(0xFF888888);

  @override
  Widget build(BuildContext context) {
    return _TerminalView(
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

class _TerminalView extends StatefulWidget {
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _TerminalView({
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
          if (messages.isEmpty) {
            return const Center(
              child: Text('\$ 等待输入…',
                  style: TextStyle(
                      color: TerminalRenderer._green,
                      fontFamily: 'monospace',
                      fontSize: 14)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) =>
                _buildMessage(context, messages[index]),
          );
        },
      ),
    );
  }

  Widget _buildMessage(BuildContext context, Message message) {
    switch (message.role) {
      case MessageRole.user:
        return _TerminalLine(
          prefix: '> ',
          prefixColor: TerminalRenderer._cyan,
          text: message.textContent,
          textColor: TerminalRenderer._cyan,
        );
      case MessageRole.system:
        return _TerminalLine(
          prefix: '[system] ',
          prefixColor: TerminalRenderer._yellow,
          text: message.textContent,
          textColor: TerminalRenderer._yellow,
        );
      case MessageRole.tool:
      case MessageRole.assistant:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: message.parts.map(_buildPart).toList(),
        );
    }
  }

  Widget _buildPart(MessagePart part) {
    switch (part) {
      case TextPart():
        return _TerminalLine(
          prefix: '~ ',
          prefixColor: TerminalRenderer._green,
          text: part.text,
          textColor: TerminalRenderer._green,
        );
      case ThinkingPart():
        return _TerminalLine(
          prefix: '[thinking] ',
          prefixColor: TerminalRenderer._gray,
          text: part.content,
          textColor: TerminalRenderer._gray,
        );
      case ToolCallPart():
        return _TerminalToolBlock(part: part);
      case CodePart():
        return _TerminalCodeBlock(part: part);
      case ApprovalPart():
        return ApprovalPartRenderer(
          part: part,
          onApprove: () => widget.dataSource.approveAction(part.id),
          onReject: () => widget.dataSource.rejectAction(part.id),
        );
      default:
        // 图片/文件/产物等用共享组件兜底
        return MessagePartRenderer(
          part: part,
          uiState: _uiState,
          onUIStateChanged: _update,
        );
    }
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
