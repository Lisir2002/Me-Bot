import 'package:flutter/material.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/build_context_l10n.dart';

/// 滑动引用回复预览条：显示被引用方名称 + 最多 2 行摘要 + 关闭按钮。
/// 位于 ChatInputBar 正上方；关闭即清空引用态。
class ReplyPreviewBar extends StatelessWidget {
  const ReplyPreviewBar({
    super.key,
    required this.message,
    required this.onCancel,
  });

  final ChatMessage message;
  final VoidCallback onCancel;

  /// 被引用方显示名称：user -> 「你」，assistant -> 「助手」。
  String _authorName(BuildContext context) {
    return message.role == 'user'
        ? context.l10n.replyLabelYou
        : context.l10n.replyLabelAssistant;
  }

  /// 去掉 [image:]/[file:] 标记后的纯文本摘要，最多约 80 字。
  String _summary() {
    var text = message.content
        .replaceAll(RegExp(r'\[image:.*?\]'), '')
        .replaceAll(RegExp(r'\[file:.*?\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return '';
    if (text.length > 80) text = '${text.substring(0, 80)}…';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _authorName(context);
    final summary = _summary();
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: cs.primary, width: 3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.reply_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: context.l10n.replyPreviewCancel,
              child: InkWell(
                onTap: onCancel,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
