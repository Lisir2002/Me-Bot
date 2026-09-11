// ignore_for_file: hardcoded_ui_string
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/snackbar.dart';
import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// no_raw_alert_dialog 白名单：全屏看图用黑底 Dialog + InteractiveViewer（非卡片式居中弹窗，AppDialog 语义不符）。
///
/// Style 10：富内容渲染（RichContent）
///
/// 综合渲染、按内容类型自适应，消息间用卡片分隔。
///  - 代码块：语言标签 + 复制 + 运行（共享 CodePartRenderer，showRunButton: true）
///  - 文件卡片：类型图标 + 大小
///  - 数据表格：Markdown 表格用原生 DataTable 渲染
///  - 图片：圆角 + 点击放大
///  - 链接：可点击
///  - 连续工具调用：用 groupConsecutiveToolCalls 聚合为 ToolGroupCard
///  - 思考过程：增强 ThinkingPartRenderer（流式自动展开）
///  - 用户引用回复：QuoteRefWidget
///  - 流式输出：末尾追加 StreamingCursor
///  - 混合内容间距：不同类型 8px，同类型连续 4px
class RichContentRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.richContent;

  @override
  Widget build(BuildContext context) {
    return _RichContentView(
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

class _RichContentView extends StatefulWidget {
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _RichContentView({
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_RichContentView> createState() => _RichContentViewState();
}

class _RichContentViewState extends State<_RichContentView> {
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
        if (messages.isEmpty) return const Center(child: Text('暂无内容'));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessageCard(context, messages[index], messages),
        );
      },
    );
  }

  /// 消息卡片：消息间用卡片分隔
  Widget _buildMessageCard(
      BuildContext context, Message message, List<Message> allMessages) {
    final theme = Theme.of(context);
    if (message.role == MessageRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 用户引用回复：气泡上方显示 QuoteRefWidget
            if (message.referencedMessageId != null)
              _buildQuoteRef(message, allMessages) ??
                  const SizedBox.shrink(),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 340),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: message.parts
                    .map((p) => _buildPart(p, overrideColor: Colors.white))
                    .toList(),
              ),
            ),
          ],
        ),
      );
    }
    if (message.role == MessageRole.system) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        child: Text(message.textContent,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic)),
      );
    }

    // 助手/工具消息：分组渲染各 part + 统一间距
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildAssistantParts(message),
      ),
    );
  }

  /// 构建用户引用回复组件：从 allMessages 查找被引用消息，取 textContent 前50字预览
  Widget? _buildQuoteRef(Message message, List<Message> allMessages) {
    Message? refMsg;
    for (final m in allMessages) {
      if (m.id == message.referencedMessageId) {
        refMsg = m;
        break;
      }
    }
    if (refMsg == null) return null;
    return QuoteRefWidget(
      senderName: refMsg.role == MessageRole.user
          ? '用户'
          : (refMsg.assistantName ?? '助手'),
      contentPreview: refMsg.textContent,
      timestamp: refMsg.timestamp,
    );
  }

  /// 构建助手消息的 parts：连续工具调用聚合为 ToolGroupCard，统一间距
  ///
  /// 间距规则：不同类型 part 之间 8px，同类型连续 part 之间 4px。
  List<Widget> _buildAssistantParts(Message message) {
    final out = <Widget>[];
    final parts = message.parts;
    final groups = groupConsecutiveToolCalls(parts);
    var groupIdx = 0;
    final isStreaming = message.isStreaming;
    int? lastTextIndex;
    String? prevType;

    // 按类型插入间距：类型变化 8px，同类型 4px
    void add(Widget w, String type) {
      if (out.isNotEmpty) {
        out.add(SizedBox(height: type == prevType ? 4 : 8));
      }
      prevType = type;
      out.add(w);
    }

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];

      // 命中工具组：聚合为 ToolGroupCard
      if (groupIdx < groups.length &&
          identical(part, groups[groupIdx].toolCalls.first)) {
        final group = groups[groupIdx];
        add(
          ToolGroupCard(
            toolCalls: group.toolCalls,
            uiState: _uiState,
            onUIStateChanged: _update,
          ),
          'toolgroup',
        );
        i += group.toolCalls.length - 1;
        groupIdx++;
        continue;
      }

      switch (part) {
        case TextPart():
          add(_RichTextBlock(text: part.text), 'text');
          lastTextIndex = out.length - 1;
        case CodePart():
          // 代码块：全宽 CodePartRenderer，带运行按钮
          final isExpanded = _uiState.expandedCodeBlockIds.contains(part.id) ||
              part.code.length < 500;
          add(
            CodePartRenderer(
              part: part,
              expanded: isExpanded,
              showRunButton: true,
              onToggleExpand: part.code.length >= 500
                  ? () => _update(_uiState.toggleCodeBlock(part.id))
                  : null,
            ),
            'code',
          );
        case ToolCallPart():
          // 未被分组覆盖的单个工具调用（兜底）
          add(
            ToolCallPartRenderer(
              part: part,
              expanded: _uiState.expandedToolCallIds.contains(part.id),
              onToggleExpand: () =>
                  _update(_uiState.toggleToolCall(part.id)),
            ),
            'tool',
          );
        case ThinkingPart():
          // 思考过程：增强渲染器，传入 isStreaming
          add(
            ThinkingPartRenderer(
              part: part,
              collapsed: true,
              onToggleCollapse: () =>
                  _update(_uiState.toggleThinking(part.id)),
              isStreaming: isStreaming,
            ),
            'thinking',
          );
        case ImagePart():
          // 图片：圆角 + 最大宽度约束 + 点击放大
          add(_ZoomableImage(part: part), 'image');
        case FilePart():
          add(FilePartRenderer(part: part), 'file');
        case ApprovalPart():
          add(
            ApprovalPartRenderer(
              part: part,
              onApprove: () => widget.dataSource.approveAction(part.id),
              onReject: () => widget.dataSource.rejectAction(part.id),
            ),
            'approval',
          );
        case ArtifactPart():
          add(ArtifactPartRenderer(part: part), 'artifact');
        case TaskPart():
          add(Text('📋 ${part.title}'), 'task');
      }
    }

    // 流式中：在最后一个 TextPart 后追加闪烁光标
    if (isStreaming && lastTextIndex != null) {
      out.insert(
        lastTextIndex + 1,
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: StreamingCursor(),
        ),
      );
    }
    return out;
  }

  Widget _buildPart(MessagePart part, {Color? overrideColor}) {
    switch (part) {
      case TextPart():
        // 文本：智能渲染表格 + 可点击链接
        return _RichTextBlock(
          text: part.text,
          textColor: overrideColor,
        );
      case CodePart():
        // 代码块：共享组件，带运行按钮
        final isExpanded = _uiState.expandedCodeBlockIds.contains(part.id) ||
            part.code.length < 500;
        return CodePartRenderer(
          part: part,
          expanded: isExpanded,
          showRunButton: true,
          onToggleExpand: part.code.length >= 500
              ? () => _update(_uiState.toggleCodeBlock(part.id))
              : null,
        );
      case ToolCallPart():
        // 紧凑 chip 样式，可展开
        return _CompactToolChip(
          part: part,
          expanded: _uiState.expandedToolCallIds.contains(part.id),
          onToggle: () => _update(_uiState.toggleToolCall(part.id)),
        );
      case ThinkingPart():
        // 思考过程：折叠块
        return ThinkingPartRenderer(
          part: part,
          collapsed: true,
          onToggleCollapse: () => _update(_uiState.toggleThinking(part.id)),
        );
      case ImagePart():
        return _ZoomableImage(part: part);
      case FilePart():
        return FilePartRenderer(part: part);
      case ApprovalPart():
        return ApprovalPartRenderer(
          part: part,
          onApprove: () => widget.dataSource.approveAction(part.id),
          onReject: () => widget.dataSource.rejectAction(part.id),
        );
      case ArtifactPart():
        return ArtifactPartRenderer(part: part);
      case TaskPart():
        return Text('📋 ${part.title}');
    }
  }
}

/// 富文本块：把 Markdown 表格抽出来用 DataTable 渲染，其余段落渲染可点击链接
class _RichTextBlock extends StatelessWidget {
  final String text;
  final Color? textColor;
  const _RichTextBlock({required this.text, this.textColor});

  @override
  Widget build(BuildContext context) {
    final blocks = _splitBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) {
        if (b is _TableBlock) return _MarkdownTable(table: b);
        return _ClickableText(text: (b as _ParaBlock).text, color: textColor);
      }).toList(),
    );
  }

  /// 把文本按行切分为段落块与表格块
  List<_Block> _splitBlocks(String text) {
    final lines = text.split('\n');
    final result = <_Block>[];
    final para = StringBuffer();
    final tableLines = <String>[];

    void flushPara() {
      if (para.toString().trim().isNotEmpty) {
        result.add(_ParaBlock(para.toString()));
      }
      para.clear();
    }

    for (final line in lines) {
      if (_isTableLine(line)) {
        tableLines.add(line);
      } else {
        if (tableLines.isNotEmpty) {
          final t = _parseTable(tableLines);
          if (t != null) result.add(t);
          tableLines.clear();
        }
        para.writeln(line);
      }
    }
    if (tableLines.isNotEmpty) {
      final t = _parseTable(tableLines);
      if (t != null) result.add(t);
    }
    flushPara();
    return result;
  }

  bool _isTableLine(String line) {
    final t = line.trim();
    return t.startsWith('|') && t.endsWith('|') && t.contains('|', 1);
  }

  List<String> _cells(String line) {
    final t = line.trim();
    return t
        .substring(1, t.length - 1)
        .split('|')
        .map((c) => c.trim())
        .toList();
  }

  bool _isSeparator(List<String> cells) =>
      cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));

  _TableBlock? _parseTable(List<String> lines) {
    if (lines.length < 2) return null;
    final header = _cells(lines[0]);
    if (!_isSeparator(_cells(lines[1]))) return null;
    final rows = lines.skip(2).map(_cells).toList();
    return _TableBlock(header: header, rows: rows);
  }
}

sealed class _Block {}

class _ParaBlock extends _Block {
  final String text;
  _ParaBlock(this.text);
}

class _TableBlock extends _Block {
  final List<String> header;
  final List<List<String>> rows;
  _TableBlock({required this.header, required this.rows});
}

/// Markdown 表格 -> 原生 DataTable
class _MarkdownTable extends StatelessWidget {
  final _TableBlock table;
  const _MarkdownTable({required this.table});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
              theme.colorScheme.surfaceContainerHighest),
          columns: table.header
              .map((h) => DataColumn(
                  label: Text(h,
                      style: const TextStyle(fontWeight: FontWeight.w600))))
              .toList(),
          rows: table.rows
              .map((r) => DataRow(
                    cells: List.generate(table.header.length, (i) {
                      final cell = i < r.length ? r[i] : '';
                      return DataCell(Text(cell));
                    }),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// 可点击链接文本（简单正则提取 http(s) URL）
class _ClickableText extends StatelessWidget {
  final String text;
  final Color? color;
  const _ClickableText({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = theme.colorScheme.primary;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(color: color);
    final uriReg = RegExp(r'https?://[^\s)]+');
    final spans = <TextSpan>[];
    int last = 0;

    for (final match in uriReg.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
            color: color ?? linkColor, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            // 简单打开：实际项目可用 url_launcher
            showAppSnackBar(context, message: '打开链接: $url');
          },
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SelectableText.rich(TextSpan(style: baseStyle, children: spans)),
    );
  }
}

/// 紧凑工具调用 chip，可展开（用户气泡内单工具调用兜底用）
class _CompactToolChip extends StatelessWidget {
  final ToolCallPart part;
  final bool expanded;
  final VoidCallback onToggle;
  const _CompactToolChip({
    required this.part,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    IconData icon;
    switch (part.status) {
      case ToolCallStatus.success:
        color = Colors.green;
        icon = Icons.check;
      case ToolCallStatus.running:
        color = Colors.blue;
        icon = Icons.autorenew;
      case ToolCallStatus.error:
        color = theme.colorScheme.error;
        icon = Icons.error;
      case ToolCallStatus.pending:
        color = Colors.grey;
        icon = Icons.hourglass_empty;
      case ToolCallStatus.cancelled:
        color = Colors.grey;
        icon = Icons.cancel;
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Icon(Icons.terminal, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(part.toolName,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (part.duration != null)
                    Text('${part.duration!.inMilliseconds}ms',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontFamily: 'monospace')),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ToolCallPartRenderer(
                part: part,
                expanded: true,
                onRetry: () {},
              ),
            ),
        ],
      ),
    );
  }
}

/// 图片：圆角显示 + 点击放大
class _ZoomableImage extends StatelessWidget {
  final ImagePart part;
  const _ZoomableImage({required this.part});

  @override
  Widget build(BuildContext context) {
    final image = part.url.startsWith('http')
        ? Image.network(part.url, fit: BoxFit.contain)
        : Image.asset(part.url, fit: BoxFit.contain);
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        // 最大宽度约束：图片不超出卡片
        constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: image,
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: part.url.startsWith('http')
                    ? Image.network(part.url)
                    : Image.asset(part.url),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
