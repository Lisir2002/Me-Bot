import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import 'snackbar.dart';

// ──────────────────────────────────────────────────────────────
// AppDialog — 中心化弹窗统一入口
//
// 来历：全仓 22 处 AlertDialog / 43 处 Dialog / 35 处 showModalBottomSheet，
// 风格五花八门（圆角 12~28、padding 8~24、按钮颜色不统一、危险操作无红色
// 警示）。本组件收敛所有中心化弹窗，与 AppSheet（底部弹层）、
// showAppSnackBar（顶部通知）形成三层反馈体系。
//
// 三层反馈体系选型：
//   阻断式确认/输入     → AppDialog（中心化，必须用户决策）
//   选项列表/长内容     → AppSheet（底部弹层，可滚动）
//   轻量通知/操作反馈   → showAppSnackBar（顶部浮层，自动消失）
//   加载中/不可中断     → AppDialog.progress（中心化，barrierDismissible=false）
//
// 用法：
//   final ok = await AppDialog.confirm(context, title: '删除', message: '...');
//   await AppDialog.alert(context, title: '成功', message: '...');
//   await AppDialog.progress(context, future: someAsync, message: '加载中...');
//   final text = await AppDialog.input(context, title: '重命名', initial: '...');
//   await AppDialog.announcement(context, title: '更新公告', content: '...');
// ──────────────────────────────────────────────────────────────

/// 弹窗按钮类型，决定颜色语义。
enum AppDialogButtonKind {
  /// 主操作（确认/保存/继续），用 primary 色。
  primary,

  /// 危险操作（删除/清除/撤销），用 error 色。
  danger,

  /// 次操作（取消/返回），用 onSurfaceVariant 色。
  secondary,
}

/// 中心化弹窗基础组件。
///
/// 统一圆角 20、surface 背景、padding 20/16。
/// 通常不直接使用，而是通过 [AppDialog.confirm] / [AppDialog.alert] 等
/// 静态方法；需要完全自定义内容时才直接构造。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.titleIcon,
    required this.content,
    this.actions = const [],
    this.maxWidth = 320,
  });

  final String? title;
  final IconData? titleIcon;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    if (titleIcon != null) ...[
                      Icon(titleIcon, size: 22, color: cs.primary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              content,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppGap.sm),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 统一按钮 ──────────────────────────────────────────────

  /// 弹窗按钮：统一高度、圆角、文字样式。
  static Widget button({
    required String label,
    required VoidCallback onPressed,
    AppDialogButtonKind kind = AppDialogButtonKind.primary,
    bool filled = true,
  }) {
    return Builder(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final Color fg = switch (kind) {
          AppDialogButtonKind.primary => filled ? cs.onPrimary : cs.primary,
          AppDialogButtonKind.danger => filled ? cs.onError : cs.error,
          AppDialogButtonKind.secondary => cs.onSurfaceVariant,
        };
        final Color bg = switch (kind) {
          AppDialogButtonKind.primary => filled ? cs.primary : Colors.transparent,
          AppDialogButtonKind.danger => filled ? cs.error : Colors.transparent,
          AppDialogButtonKind.secondary => Colors.transparent,
        };
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 确认弹窗 ──────────────────────────────────────────────

  /// 确认弹窗：标题 + 内容 + 确认/取消。
  ///
  /// 返回 `true` 表示用户点确认，`false` 表示取消或关闭。
  /// 危险操作传 [danger] = true，确认按钮用 error 色。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确认',
    String cancelText = '取消',
    bool danger = false,
    IconData? icon,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        titleIcon: icon ?? (danger ? Icons.error_outline : Icons.help_outline),
        content: Text(
          message,
          style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.75), height: 1.5),
        ),
        actions: [
          button(
            label: cancelText,
            kind: AppDialogButtonKind.secondary,
            filled: false,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          button(
            label: confirmText,
            kind: danger ? AppDialogButtonKind.danger : AppDialogButtonKind.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── 通知弹窗 ──────────────────────────────────────────────

  /// 通知弹窗：标题 + 内容 + 单按钮（知道了）。
  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = '知道了',
    IconData? icon,
    NotificationType? type,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final IconData defaultIcon = switch (type) {
      NotificationType.success => Icons.check_circle_outline,
      NotificationType.error => Icons.error_outline,
      NotificationType.warning => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        titleIcon: icon ?? defaultIcon,
        content: Text(
          message,
          style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.75), height: 1.5),
        ),
        actions: [
          button(
            label: buttonText,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  // ── 进度弹窗 ──────────────────────────────────────────────

  /// 进度弹窗：加载指示器 + 文字，不可点击蒙层关闭。
  ///
  /// 传入 [future] 时自动等待完成后关闭并返回其结果；
  /// 不传 future 时需手动调用 Navigator.pop 关闭。
  static Future<T?> progress<T>(
    BuildContext context, {
    required String message,
    Future<T>? future,
  }) async {
    T? result;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final fut = future;
        if (fut != null) {
          fut.then((r) {
            result = r;
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          }).catchError((_) {
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          });
        }
        return AppDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 15, color: Theme.of(ctx).colorScheme.onSurface),
                ),
              ),
            ],
          ),
        );
      },
    );
    return result;
  }

  // ── 输入弹窗 ──────────────────────────────────────────────

  /// 输入弹窗：标题 + 输入框 + 确认/取消。
  ///
  /// 返回输入的文本；用户取消或关闭时返回 null。
  static Future<String?> input(
    BuildContext context, {
    required String title,
    String? initialText,
    String hintText = '',
    String confirmText = '确认',
    String cancelText = '取消',
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: initialText);
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          button(
            label: cancelText,
            kind: AppDialogButtonKind.secondary,
            filled: false,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          button(
            label: confirmText,
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  // ── 公告弹窗 ──────────────────────────────────────────────

  /// 公告弹窗：标题 + 内容 + "不再提示"勾选 + 关闭。
  ///
  /// [onDontShowAgain] 回调在用户勾选"不再提示"并关闭时触发。
  static Future<void> announcement(
    BuildContext context, {
    required String title,
    required String content,
    String buttonText = '我知道了',
    String dontShowAgainText = '不再提示',
    IconData icon = Icons.campaign_outlined,
    ValueChanged<bool>? onDontShowAgain,
  }) async {
    var dontShow = false;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          title: title,
          titleIcon: icon,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(0.75),
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => dontShow = !dontShow),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: dontShow,
                          onChanged: (v) => setState(() => dontShow = v ?? false),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dontShowAgainText,
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            button(
              label: buttonText,
              onPressed: () {
                onDontShowAgain?.call(dontShow);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
