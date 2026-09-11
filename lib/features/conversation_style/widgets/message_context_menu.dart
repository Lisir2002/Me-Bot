// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../l10n/style_l10n.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';

/// 消息长按上下文菜单 —— 统一复制/引用/重新生成/分享/删除
///
/// 渲染器只负责在用户长按后调用 [showMessageContextMenu]，
/// 各动作通过回调交回宿主处理（符合"渲染器不持业务逻辑"约束）。
class MessageContextMenu extends StatelessWidget {
  final Message message;
  final VoidCallback onCopy;
  final VoidCallback onQuote;
  final VoidCallback onRetry;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const MessageContextMenu({
    super.key,
    required this.message,
    required this.onCopy,
    required this.onQuote,
    required this.onRetry,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.copy,
            label: StyleL10n.menuCopy,
            semantics: StyleL10n.copyActionSemantic,
            onTap: onCopy,
          ),
          _Tile(
            icon: Icons.format_quote,
            label: StyleL10n.menuQuote,
            semantics: StyleL10n.quoteActionSemantic,
            onTap: onQuote,
          ),
          // 仅助手消息提供重新生成
          if (message.role == MessageRole.assistant)
            _Tile(
              icon: Icons.refresh,
              label: StyleL10n.menuRetry,
              semantics: StyleL10n.retryActionSemantic,
              onTap: onRetry,
            ),
          _Tile(
            icon: Icons.share,
            label: StyleL10n.menuShare,
            semantics: StyleL10n.shareActionSemantic,
            onTap: onShare,
          ),
          _Tile(
            icon: Icons.delete_outline,
            label: StyleL10n.menuDelete,
            semantics: StyleL10n.deleteActionSemantic,
            destructive: true,
            onTap: onDelete,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final bool destructive;

  const _Tile({
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        destructive ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      label: semantics,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}

/// 便捷方法：在底部弹出消息上下文菜单
void showMessageContextMenu(
  BuildContext context,
  Message message, {
  required VoidCallback onCopy,
  required VoidCallback onQuote,
  required VoidCallback onRetry,
  required VoidCallback onShare,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => MessageContextMenu(
      message: message,
      onCopy: onCopy,
      onQuote: onQuote,
      onRetry: onRetry,
      onShare: onShare,
      onDelete: onDelete,
    ),
  );
}
