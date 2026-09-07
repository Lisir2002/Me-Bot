import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

// ──────────────────────────────────────────────────────────────
// AppSheet — 底部弹层模板（iOS mini-sheet）
//
// 收敛 showModalBottomSheet 里重复的：顶部圆角、surface 底色、
// 拖拽把手、可选标题、最大高度、键盘避让、可选底部按钮。
// 采用项目里已验证的布局模式：
//   ConstrainedBox(maxHeight) + SingleChildScrollView + Column(min)
//
// 用法（以语言选择 / 推理预算这类简单选项弹层为例）：
//   showAppSheet(context: context, builder: AppSheet(
//     title: l10n.xxx,
//     children: [
//       AppSheetOptionRow(...)  或任意行 widget
//     ],
//   ));
//
// 复杂交互弹层（DraggableScrollableSheet / 内部 Tab / 居中标题 +
// 左右操作按钮）不适用本模板，保持自建。
// ──────────────────────────────────────────────────────────────

/// 弹层内一个分组
class AppSheetSection {
  final String? header;
  final List<Widget> children;
  const AppSheetSection({this.header, required this.children});
}

/// 弹层主体（safeArea + 键盘避让由 showAppSheet 统一处理）
class AppSheet extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final bool showGrabber;
  final Widget? footer;
  final double maxHeight;
  final EdgeInsetsGeometry contentPadding;

  const AppSheet({
    super.key,
    this.title,
    required this.children,
    this.showGrabber = true,
    this.footer,
    this.maxHeight = 0.8,
    this.contentPadding = const EdgeInsets.fromLTRB(AppGap.xs, 4, AppGap.xs, AppGap.sm),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final maxH = MediaQuery.of(context).size.height * maxHeight;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showGrabber) ...[
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
            Padding(
              padding: contentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xs, AppGap.sm, AppGap.sm),
                        child: Text(title!, style: AppText.h2(tt).copyWith(color: cs.onSurface)),
                      ),
                    ),
                  ...children,
                  if (footer != null) ...[
                    const SizedBox(height: AppGap.xs),
                    footer!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开 AppSheet：统一 safeArea + 顶部圆角 + 键盘避让
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget builder,
  bool isScrollControlled = true,
  double? borderRadius = AppRadius.lg,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: cs.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius ?? AppRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: builder,
      ),
    ),
  );
}