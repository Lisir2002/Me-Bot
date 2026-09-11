// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';

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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          // 头部：工具名 + 状态
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
                    if (onRetry != null)
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
class ThinkingPartRenderer extends StatelessWidget {
  final ThinkingPart part;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const ThinkingPartRenderer({
    super.key,
    required this.part,
    this.collapsed = true,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            onTap: onToggleCollapse,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.psychology,
                      size: 16, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '思考过程',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (part.tokenCount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${part.tokenCount} tokens',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (part.duration != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${part.duration!.inSeconds}s',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                part.content,
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

/// 审批部分渲染器
class ApprovalPartRenderer extends StatelessWidget {
  final ApprovalPart part;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const ApprovalPartRenderer({
    super.key,
    required this.part,
    this.onApprove,
    this.onReject,
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
          if (isPending && (onApprove != null || onReject != null)) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
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
                const SizedBox(width: 8),
                if (onApprove != null)
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('批准'),
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
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  )
                : Image.asset(
                    part.url,
                    fit: BoxFit.contain,
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
    }
  }
}
