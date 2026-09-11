// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import 'agent_enhanced_widgets.dart';

/// 共享的消息部分渲染器 —— 所有样式可以复用这些基础渲染组件
///
/// 每种样式可以直接使用这些组件，也可以自定义外观。
/// 这确保了所有样式对同一种 MessagePart 的渲染逻辑一致。

/// 文本部分渲染器
class TextPartRenderer extends StatelessWidget {
  final TextPart part;
  final TextStyle? style;
  final TextAlign? textAlign;

  const TextPartRenderer({
    super.key,
    required this.part,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: Text(
        part.text,
        style: style ?? theme.textTheme.bodyMedium,
        textAlign: textAlign,
      ),
    );
  }
}

/// 代码部分渲染器
class CodePartRenderer extends StatefulWidget {
  final CodePart part;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final bool showCopyButton;
  final bool showRunButton;
  final VoidCallback? onRun;

  const CodePartRenderer({
    super.key,
    required this.part,
    this.expanded = true,
    this.onToggleExpand,
    this.showCopyButton = true,
    this.showRunButton = false,
    this.onRun,
  });

  @override
  State<CodePartRenderer> createState() => _CodePartRendererState();
}

class _CodePartRendererState extends State<CodePartRenderer> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C34) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 代码头部：语言标签 + 操作按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  widget.part.filename ?? widget.part.language,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (widget.showRunButton)
                  TextButton.icon(
                    onPressed: widget.onRun,
                    icon: const Icon(Icons.play_arrow, size: 14),
                    label: const Text('运行'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                if (widget.showCopyButton)
                  IconButton(
                    icon: Icon(
                      _copied ? Icons.check : Icons.content_copy,
                      size: 16,
                    ),
                    onPressed: _copyCode,
                    tooltip: '复制代码',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(28, 28),
                    ),
                  ),
              ],
            ),
          ),
          // 代码内容
          Padding(
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              widget.part.code,
              language: _mapLanguage(widget.part.language),
              theme: isDark ? atomOneDarkTheme : githubTheme,
              padding: EdgeInsets.zero,
              textStyle: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          // 折叠/展开
          if (widget.onToggleExpand != null)
            InkWell(
              onTap: widget.onToggleExpand,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                child: Text(
                  widget.expanded ? '收起' : '展开全部',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _copyCode() {
    // 简单复制（实际项目中使用 Clipboard.setData）
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _mapLanguage(String lang) {
    const map = {
      'dart': 'dart',
      'python': 'python',
      'javascript': 'javascript',
      'js': 'javascript',
      'typescript': 'typescript',
      'ts': 'typescript',
      'java': 'java',
      'kotlin': 'kotlin',
      'swift': 'swift',
      'go': 'go',
      'golang': 'go',
      'rust': 'rust',
      'c': 'c',
      'cpp': 'cpp',
      'c++': 'cpp',
      'csharp': 'csharp',
      'ruby': 'ruby',
      'php': 'php',
      'sql': 'sql',
      'bash': 'bash',
      'shell': 'bash',
      'sh': 'bash',
      'json': 'json',
      'yaml': 'yaml',
      'yml': 'yaml',
      'xml': 'xml',
      'html': 'xml',
      'css': 'css',
      'markdown': 'markdown',
      'md': 'markdown',
      'plaintext': 'plaintext',
    };
    return map[lang.toLowerCase()] ?? 'plaintext';
  }
}

/// 工具调用部分渲染器
class ToolCallPartRenderer extends StatelessWidget {
  final ToolCallPart part;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onRetry;

  const ToolCallPartRenderer({
    super.key,
    required this.part,
    this.expanded = false,
    this.onToggleExpand,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(theme);
    final statusIcon = _statusIcon();
    final statusText = _statusText();
    final showProgress = part.status == ToolCallStatus.running &&
        part.progress != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: part.isStalled
              ? Colors.orange
              : (part.status == ToolCallStatus.error
                  ? theme.colorScheme.error.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant),
          width: part.isStalled || part.status == ToolCallStatus.error ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // 头部：工具名 + 状态 + 信心徽章 + 耗时
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      part.toolName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  // 信心徽章（Devin 风格交通灯）
                  if (part.confidence != null) ...[
                    ConfidenceBadge(level: part.confidence!),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    statusText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                  if (part.duration != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${part.duration!.inMilliseconds}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // 执行进度条（Claude Code 风格，长时间运行工具）
          if (showProgress)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ToolProgressBar(progress: part.progress!),
            ),
          // 停滞警告（Cursor 教训：30秒无进展提示）
          if (part.isStalled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: StalledToolWarning(
                stalledSeconds: 30,
                onCancel: onRetry,
              ),
            ),
          // 展开内容
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (part.thinking != null) ...[
                    Text('思考',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 4),
                    Text(part.thinking!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    const SizedBox(height: 8),
                  ],
                  Text('参数',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _prettyJson(part.arguments),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (part.result != null) ...[
                    const SizedBox(height: 8),
                    Text('结果',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        part.result.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (part.status == ToolCallStatus.error &&
                      part.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        part.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    // 错误恢复建议（Claude Code 风格：可操作建议 + 一键重试）
                    if (part.recoverySuggestions != null &&
                        part.recoverySuggestions!.isNotEmpty)
                      ErrorRecoverySuggestions(
                        suggestions: part.recoverySuggestions!,
                        onRetry: onRetry,
                      ),
                    if (onRetry != null &&
                        (part.recoverySuggestions == null ||
                            part.recoverySuggestions!.isEmpty))
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('重试'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(ThemeData theme) {
    switch (part.status) {
      case ToolCallStatus.pending:
        return theme.colorScheme.onSurfaceVariant;
      case ToolCallStatus.running:
        return Colors.blue;
      case ToolCallStatus.success:
        return Colors.green;
      case ToolCallStatus.error:
        return theme.colorScheme.error;
      case ToolCallStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (part.status) {
      case ToolCallStatus.pending:
        return Icons.hourglass_empty;
      case ToolCallStatus.running:
        return Icons.autorenew;
      case ToolCallStatus.success:
        return Icons.check_circle;
      case ToolCallStatus.error:
        return Icons.error;
      case ToolCallStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _statusText() {
    switch (part.status) {
      case ToolCallStatus.pending:
        return '等待中';
      case ToolCallStatus.running:
        return '执行中';
      case ToolCallStatus.success:
        return '成功';
      case ToolCallStatus.error:
        return '失败';
      case ToolCallStatus.cancelled:
        return '已取消';
    }
  }

  String _prettyJson(Map<String, dynamic> map) {
    if (map.isEmpty) return '{}';
    final buffer = StringBuffer('{\n');
    for (final entry in map.entries) {
      buffer.write('  "${entry.key}": ');
      final value = entry.value;
      if (value is String) {
        buffer.write('"${value.length > 100 ? '${value.substring(0, 100)}...' : value}"');
      } else {
        buffer.write(value.toString());
      }
      buffer.write('\n');
    }
    buffer.write('}');
    return buffer.toString();
  }
}

/// 思考部分渲染器
///
/// 流式中（isStreaming=true）：自动展开，头部脉冲小圆点 + "思考中..."
/// 完成后：自动折叠为一行 "✦ 思考 · Xs" + 首句摘要（前30字）
/// 保留手动点击切换。
///
/// [streamingCollapsed]：为 true 时即使流式中也保持折叠（极简样式用，
/// 只显示脉冲点 + "思考中" 一行，不展开全文）。默认 false，行为不变。
class ThinkingPartRenderer extends StatefulWidget {
  final ThinkingPart part;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  /// 是否正在流式输出中 —— 为 true 时自动展开并显示脉冲点
  final bool isStreaming;

  /// 即使流式中也保持折叠（极简样式用）
  final bool streamingCollapsed;

  const ThinkingPartRenderer({
    super.key,
    required this.part,
    this.collapsed = true,
    this.onToggleCollapse,
    this.isStreaming = false,
    this.streamingCollapsed = false,
  });

  @override
  State<ThinkingPartRenderer> createState() => _ThinkingPartRendererState();
}

class _ThinkingPartRendererState extends State<ThinkingPartRenderer> {
  /// 用户是否手动切换过（手动切换后不再自动改变折叠状态）
  bool _userToggled = false;

  /// 实际生效的折叠状态
  late bool _effectiveCollapsed;

  @override
  void initState() {
    super.initState();
    _effectiveCollapsed = widget.collapsed;
  }

  @override
  void didUpdateWidget(ThinkingPartRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果外部传入的 collapsed 变化了且用户没手动切换，跟随外部
    if (!_userToggled && widget.collapsed != oldWidget.collapsed) {
      _effectiveCollapsed = widget.collapsed;
    }
    // 自动行为：流式中自动展开，完成后自动折叠；
    // streamingCollapsed=true 时即使流式中也保持折叠（极简样式）
    if (!_userToggled) {
      if (widget.isStreaming && !widget.streamingCollapsed) {
        _effectiveCollapsed = false;
      } else {
        _effectiveCollapsed = true;
      }
    }
  }

  void _handleTap() {
    _userToggled = true;
    setState(() => _effectiveCollapsed = !_effectiveCollapsed);
    widget.onToggleCollapse?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStreaming = widget.isStreaming;
    final summary = widget.part.content.trim();
    final preview = summary.length > 30 ? '${summary.substring(0, 30)}…' : summary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.secondaryContainer,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggleCollapse != null ? _handleTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // 流式中显示脉冲点，完成后显示静态图标
                  if (isStreaming)
                    const _PulseDot(color: Colors.purple, size: 10)
                  else
                    Icon(Icons.psychology,
                        size: 16, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    isStreaming ? '思考中...' : '思考过程',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isStreaming)
                    const SizedBox.shrink()
                  else ...[
                    if (widget.part.tokenCount != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${widget.part.tokenCount} tokens',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.part.duration != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${widget.part.duration!.inSeconds}s',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                  const Spacer(),
                  // 折叠态右侧显示首句摘要
                  if (_effectiveCollapsed && preview.isNotEmpty && !isStreaming)
                    Expanded(
                      child: Text(
                        preview,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  Icon(
                    _effectiveCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!_effectiveCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                widget.part.content,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 脉冲小圆点 —— 透明度 0.3↔1 循环，1s 周期
class _PulseDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulseDot({required this.color, required this.size});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: 0.3 + 0.7 * _controller.value,
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

/// 审批部分渲染器
///
/// 参考 Claude Code 的三选项审批设计：
/// ✅ 允许一次 / 🚫 拒绝（附原因） / 📌 本会话始终允许
class ApprovalPartRenderer extends StatelessWidget {
  final ApprovalPart part;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  /// 本会话始终允许此类操作（Claude Code `a` 选项）
  final VoidCallback? onAllowSession;

  const ApprovalPartRenderer({
    super.key,
    required this.part,
    this.onApprove,
    this.onReject,
    this.onAllowSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = part.status == ApprovalStatus.pending;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPending
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending ? Icons.security : Icons.verified,
                size: 18,
                color: isPending
                    ? theme.colorScheme.primary
                    : (part.status == ApprovalStatus.approved
                        ? Colors.green
                        : theme.colorScheme.error),
              ),
              const SizedBox(width: 8),
              Text(
                part.action,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _StatusBadge(status: part.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            part.description,
            style: theme.textTheme.bodyMedium,
          ),
          if (part.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: part.details.entries
                  .map((e) => Chip(
                        label: Text('${e.key}: ${e.value}'),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          // 拒绝原因（Claude Code 风格：拒绝时用户输入的文本作为反馈发送给模型）
          if (part.status == ApprovalStatus.rejected &&
              part.rejectReason != null &&
              part.rejectReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.feedback, size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '拒绝原因：${part.rejectReason}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 本会话始终允许标记
          if (part.allowSession) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.rule_folder, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  '本会话已自动允许此类操作',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (isPending && (onApprove != null || onReject != null)) ...[
            const SizedBox(height: 12),
            // 三选项审批（Claude Code 风格：允许一次 / 拒绝 / 本会话始终允许）
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (onReject != null)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('拒绝'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                if (onAllowSession != null)
                  OutlinedButton.icon(
                    onPressed: onAllowSession,
                    icon: const Icon(Icons.rule_folder, size: 16),
                    label: const Text('始终允许'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                  ),
                if (onApprove != null)
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('允许一次'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ApprovalStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final Color color;
    late final String text;
    switch (status) {
      case ApprovalStatus.pending:
        color = Colors.orange;
        text = '待审批';
      case ApprovalStatus.approved:
        color = Colors.green;
        text = '已通过';
      case ApprovalStatus.rejected:
        color = theme.colorScheme.error;
        text = '已拒绝';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 图片部分渲染器
class ImagePartRenderer extends StatelessWidget {
  final ImagePart part;
  final double? maxWidth;

  const ImagePartRenderer({
    super.key,
    required this.part,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      constraints: BoxConstraints(maxWidth: maxWidth ?? 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: part.url.startsWith('http')
                ? Image.network(
                    part.url,
                    fit: BoxFit.contain,
                    cacheWidth: 800, // 降采样解码，降低长列表滚动内存
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  )
                : Image.asset(
                    part.url,
                    fit: BoxFit.contain,
                    cacheWidth: 800,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
          ),
          if (part.caption != null) ...[
            const SizedBox(height: 4),
            Text(
              part.caption!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 文件部分渲染器
class FilePartRenderer extends StatelessWidget {
  final FilePart part;
  final VoidCallback? onTap;

  const FilePartRenderer({
    super.key,
    required this.part,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(_fileIcon(part.mimeType),
                size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_formatSize(part.size)} · ${part.mimeType}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.download, size: 18),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return Icons.image;
    }
    if (mimeType.startsWith('video/')) {
      return Icons.videocam;
    }
    if (mimeType.startsWith('audio/')) {
      return Icons.audiotrack;
    }
    if (mimeType.contains('pdf')) {
      return Icons.picture_as_pdf;
    }
    if (mimeType.contains('zip') || mimeType.contains('tar')) {
      return Icons.folder_zip;
    }
    if (mimeType.contains('text') || mimeType.contains('json')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 产物部分渲染器
class ArtifactPartRenderer extends StatelessWidget {
  final ArtifactPart part;
  final VoidCallback? onOpen;

  const ArtifactPartRenderer({
    super.key,
    required this.part,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primaryContainer),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_artifactIcon(part.type),
                  color: theme.colorScheme.onPrimary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_typeLabel(part.type)} · 点击在画布中打开',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, size: 20),
          ],
        ),
      ),
    );
  }

  IconData _artifactIcon(ArtifactType type) {
    switch (type) {
      case ArtifactType.document:
        return Icons.description;
      case ArtifactType.code:
        return Icons.code;
      case ArtifactType.image:
        return Icons.image;
      case ArtifactType.chart:
        return Icons.bar_chart;
      case ArtifactType.web:
        return Icons.language;
      case ArtifactType.table:
        return Icons.table_chart;
    }
  }

  String _typeLabel(ArtifactType type) {
    switch (type) {
      case ArtifactType.document:
        return '文档';
      case ArtifactType.code:
        return '代码';
      case ArtifactType.image:
        return '图片';
      case ArtifactType.chart:
        return '图表';
      case ArtifactType.web:
        return '网页';
      case ArtifactType.table:
        return '表格';
    }
  }
}

/// 通用的消息部分渲染调度器 —— 根据 part 类型选择对应的渲染器
class MessagePartRenderer extends StatelessWidget {
  final MessagePart part;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const MessagePartRenderer({
    super.key,
    required this.part,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (part) {
      case TextPart():
        return TextPartRenderer(part: part as TextPart);
      case CodePart():
        final codePart = part as CodePart;
        final isExpanded = uiState.expandedCodeBlockIds.contains(codePart.id) ||
            codePart.code.length < 500;
        return CodePartRenderer(
          part: codePart,
          expanded: isExpanded,
          onToggleExpand: codePart.code.length >= 500
              ? () => onUIStateChanged(uiState.toggleCodeBlock(codePart.id))
              : null,
        );
      case ToolCallPart():
        final toolPart = part as ToolCallPart;
        final isExpanded = uiState.expandedToolCallIds.contains(toolPart.id);
        return ToolCallPartRenderer(
          part: toolPart,
          expanded: isExpanded,
          onToggleExpand: () =>
              onUIStateChanged(uiState.toggleToolCall(toolPart.id)),
        );
      case ThinkingPart():
        final thinkPart = part as ThinkingPart;
        final isCollapsed = uiState.collapsedThinkingIds.contains(thinkPart.id);
        return ThinkingPartRenderer(
          part: thinkPart,
          collapsed: isCollapsed,
          onToggleCollapse: () =>
              onUIStateChanged(uiState.toggleThinking(thinkPart.id)),
        );
      case ApprovalPart():
        return ApprovalPartRenderer(part: part as ApprovalPart);
      case ImagePart():
        return ImagePartRenderer(part: part as ImagePart);
      case FilePart():
        return FilePartRenderer(part: part as FilePart);
      case ArtifactPart():
        return ArtifactPartRenderer(part: part as ArtifactPart);
      case TaskPart():
        // 单个任务子项用 TaskListRenderer 包装（任务列表通常成组出现）
        return TaskListRenderer(tasks: [part as TaskPart]);
    }
  }
}

// ==========================================================================
// P0 优化组件 —— 工具分组 / 引用回复 / 流式光标
// ==========================================================================

/// 工具分组信息 —— 一组连续的 ToolCallPart 的聚合元数据
class ToolGroupInfo {
  /// 组内所有工具调用
  final List<ToolCallPart> toolCalls;

  /// 工具族名称（如 "读取"、"编辑"、"搜索"、"执行"）
  final String familyName;

  /// 组内工具数量
  int get count => toolCalls.length;

  /// 总耗时（所有已完成工具的 duration 之和）
  final Duration totalDuration;

  /// 是否全部完成
  final bool allCompleted;

  /// 是否有正在运行/等待中的工具
  final bool hasRunning;

  /// 是否有错误
  final bool hasError;

  const ToolGroupInfo({
    required this.toolCalls,
    required this.familyName,
    required this.totalDuration,
    required this.allCompleted,
    required this.hasRunning,
    required this.hasError,
  });
}

/// 工具族映射 —— 根据工具名归类
String _familyNameFor(String toolName) {
  final lower = toolName.toLowerCase();
  // read 类
  const readTools = ['pdf_extract', 'file_read', 'web.fetch', 'web_fetch', 'read', 'grep', 'search'];
  // edit 类
  const editTools = ['edit', 'write', 'create_file', 'save_file'];
  // search 类
  const searchTools = ['search', 'web_search', 'grep'];
  // code 类
  const codeTools = ['code_executor', 'data_analyze', 'run_code', 'exec'];

  if (readTools.contains(lower) || lower.contains('read') || lower.contains('fetch')) {
    return '读取';
  }
  if (editTools.contains(lower) || lower.contains('edit') || lower.contains('write')) {
    return '编辑';
  }
  if (searchTools.contains(lower) || lower.contains('search') || lower.contains('grep')) {
    return '搜索';
  }
  if (codeTools.contains(lower) || lower.contains('exec') || lower.contains('code')) {
    return '执行';
  }
  // 其他返回原始工具名
  return toolName;
}

/// 将连续的 ToolCallPart 分组，返回分组信息列表（不修改原列表）
///
/// 扫描 parts 列表，将连续的 ToolCallPart 合并为一组；
/// 非 ToolCallPart 会打断分组。
List<ToolGroupInfo> groupConsecutiveToolCalls(List<MessagePart> parts) {
  final groups = <ToolGroupInfo>[];
  List<ToolCallPart>? currentGroup;
  String? currentFamily;

  void flush() {
    if (currentGroup != null && currentGroup!.isNotEmpty) {
      final totalMs = currentGroup!
          .where((t) => t.duration != null)
          .fold<int>(0, (sum, t) => sum + t.duration!.inMilliseconds);
      groups.add(ToolGroupInfo(
        toolCalls: List.unmodifiable(currentGroup!),
        familyName: currentFamily ?? '工具',
        totalDuration: Duration(milliseconds: totalMs),
        allCompleted: currentGroup!.every((t) => t.isCompleted),
        hasRunning: currentGroup!.any((t) =>
            t.status == ToolCallStatus.running ||
            t.status == ToolCallStatus.pending),
        hasError: currentGroup!.any((t) => t.status == ToolCallStatus.error),
      ));
    }
    currentGroup = null;
    currentFamily = null;
  }

  for (final part in parts) {
    if (part is ToolCallPart) {
      final family = _familyNameFor(part.toolName);
      // 同工具族才继续合并
      if (currentGroup == null) {
        currentGroup = [part];
        currentFamily = family;
      } else if (family == currentFamily) {
        currentGroup!.add(part);
      } else {
        flush();
        currentGroup = [part];
        currentFamily = family;
      }
    } else {
      flush();
    }
  }
  flush();

  return groups;
}

/// 工具调用分组卡片 —— 将连续的多个 ToolCallPart 聚合显示
///
/// 折叠态：一行显示 [工具族图标] 工具族名 ×N · 总耗时 · 状态点
/// 展开态：逐行列出每个 ToolCallPart（复用 ToolCallPartRenderer）
/// 自动行为：有工具 running/pending 时自动展开；全部完成后自动折叠
class ToolGroupCard extends StatefulWidget {
  /// 连续的工具调用列表
  final List<ToolCallPart> toolCalls;

  /// 外部控制的展开状态（可选，为 null 时内部自管理）
  final bool? expanded;

  /// 手动切换回调
  final VoidCallback? onToggleExpand;

  /// UI 状态（用于每个子 ToolCallPart 的展开状态）
  final ConversationUIState uiState;

  /// UI 状态更新回调
  final void Function(ConversationUIState) onUIStateChanged;

  const ToolGroupCard({
    super.key,
    required this.toolCalls,
    this.expanded,
    this.onToggleExpand,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  State<ToolGroupCard> createState() => _ToolGroupCardState();
}

class _ToolGroupCardState extends State<ToolGroupCard> {
  /// 用户是否手动切换过
  bool _userToggled = false;

  /// 内部折叠状态
  late bool _internalExpanded;

  @override
  void initState() {
    super.initState();
    _internalExpanded = widget.expanded ?? _shouldAutoExpand();
  }

  @override
  void didUpdateWidget(ToolGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部传入 expanded 时优先跟随
    if (widget.expanded != null) {
      _internalExpanded = widget.expanded!;
      return;
    }
    // 自动行为：有运行中工具自动展开，全部完成后自动折叠
    if (!_userToggled) {
      _internalExpanded = _shouldAutoExpand();
    }
  }

  bool _shouldAutoExpand() {
    return widget.toolCalls.any((t) =>
        t.status == ToolCallStatus.running ||
        t.status == ToolCallStatus.pending);
  }

  bool get _hasError => widget.toolCalls.any((t) => t.status == ToolCallStatus.error);

  bool get _hasRunning => widget.toolCalls.any((t) =>
      t.status == ToolCallStatus.running || t.status == ToolCallStatus.pending);

  Duration get _totalDuration {
    final ms = widget.toolCalls
        .where((t) => t.duration != null)
        .fold<int>(0, (sum, t) => sum + t.duration!.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  String get _familyName => widget.toolCalls.isEmpty
      ? '工具'
      : _familyNameFor(widget.toolCalls.first.toolName);

  void _handleTap() {
    _userToggled = true;
    setState(() => _internalExpanded = !_internalExpanded);
    widget.onToggleExpand?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.toolCalls.length;
    final durationMs = _totalDuration.inMilliseconds;

    // 状态颜色与图标
    Color statusColor;
    IconData statusIcon;
    if (_hasError) {
      statusColor = theme.colorScheme.error;
      statusIcon = Icons.error;
    } else if (_hasRunning) {
      statusColor = Colors.blue;
      statusIcon = Icons.autorenew;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // 折叠态头部
          InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // 族图标
                  Icon(_familyIcon(_familyName), size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  // 族名 + 数量
                  Text(
                    '$_familyName ×$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 总耗时
                  if (durationMs > 0)
                    Text(
                      '$durationMs ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  const Spacer(),
                  // 状态指示：运行中脉冲点 / 完成对勾 / 错误叉
                  if (_hasRunning)
                    const _PulseDot(color: Colors.blue, size: 8)
                  else
                    Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 8),
                  // 旋转箭头
                  AnimatedRotation(
                    turns: _internalExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开/折叠内容动画
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _internalExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.toolCalls.map((toolPart) {
                  return ToolCallPartRenderer(
                    part: toolPart,
                    expanded: widget.uiState.expandedToolCallIds.contains(toolPart.id),
                    onToggleExpand: () => widget.onUIStateChanged(
                      widget.uiState.toggleToolCall(toolPart.id),
                    ),
                    onRetry: () {},
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _familyIcon(String family) {
    switch (family) {
      case '读取':
        return Icons.description;
      case '编辑':
        return Icons.edit;
      case '搜索':
        return Icons.search;
      case '执行':
        return Icons.bug_report;
      default:
        return Icons.build;
    }
  }
}

/// 用户消息引用回复组件 —— 左侧色条 + 发送者 + 截断内容
class QuoteRefWidget extends StatelessWidget {
  /// 被引用消息的发送者
  final String senderName;

  /// 被引用消息的内容摘要（前50字）
  final String contentPreview;

  /// 时间戳
  final DateTime? timestamp;

  /// 点击跳转到原消息
  final VoidCallback? onTap;

  const QuoteRefWidget({
    super.key,
    required this.senderName,
    required this.contentPreview,
    this.timestamp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = contentPreview.length > 50
        ? '${contentPreview.substring(0, 50)}…'
        : contentPreview;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 小头像：首字母圆圈
            CircleAvatar(
              radius: 10,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                senderName.isNotEmpty ? senderName[0] : '?',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 发送者 · 时间
                  Text(
                    timestamp != null
                        ? '$senderName · ${_formatTime(timestamp!)}'
                        : senderName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 内容摘要（最多 2 行）
                  Text(
                    preview,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 流式输出闪烁光标
class StreamingCursor extends StatelessWidget {
  final Color? color;

  const StreamingCursor({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cursorColor = color ?? theme.colorScheme.primary;

    return _CursorBlink(color: cursorColor);
  }
}

class _CursorBlink extends StatefulWidget {
  final Color color;
  const _CursorBlink({required this.color});

  @override
  State<_CursorBlink> createState() => _CursorBlinkState();
}

class _CursorBlinkState extends State<_CursorBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _controller.value,
          child: Container(
            width: 2,
            height: 16,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }
}
