import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';
import 'ios_tactile.dart';

// ──────────────────────────────────────────────────────────────
// AppPage — 页面模板
//
// 新建页面直接套用这个，省掉重复写 Scaffold + AppBar + body padding。
// 默认行为：
//   - AppBar 透明、无 elevation（延续 Material 3 沉浸式顶栏风格）
//   - 自动加 leading back 按钮（仅当 showBack = true）
//   - body 包裹 SafeArea + 默认 padding
//   - 默认 scrollable = true（body 被 ListView 包一层，自动支持键盘避让）
//
// 使用示例（见 lib/features/settings/pages/settings_page.dart）：
//   class MyNewPage extends StatelessWidget {
//     @override
//     Widget build(BuildContext context) {
//       final l10n = AppLocalizations.of(context)!;
//       return AppPage(
//         title: l10n.myNewPageTitle,
//         actions: [IconButton(icon: Icon(Icons.add), onPressed: _add)],
//         body: Column(children: [...]),
//       );
//     }
//   }
// ──────────────────────────────────────────────────────────────

class AppPage extends StatelessWidget {
  /// 顶栏标题（推荐传入 l10n 字符串）
  final String title;

  /// 页面主体内容
  final Widget body;

  /// 顶栏右侧按钮列表
  final List<Widget>? actions;

  /// 自定义 leading —— 如果传了就完全覆盖默认 back 按钮
  final Widget? leading;

  /// 是否自动显示 back 按钮（push 进来的子页面默认 true）
  final bool showBack;

  /// floating action button
  final Widget? floatingActionButton;

  /// drawer（左侧抽屉）
  final Widget? drawer;

  /// endDrawer（右侧抽屉）
  final Widget? endDrawer;

  /// body padding —— 默认 AppPagePadding.hv
  final EdgeInsetsGeometry bodyPadding;

  /// body 是否包 ListView（自动支持滚动 + 键盘避让），默认 true
  final bool scrollable;

  /// 是否包 SafeArea，默认 true
  final bool safeArea;

  /// Scaffold 背景色 —— 默认 null → Theme.surface
  final Color? backgroundColor;

  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.showBack = true,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.bodyPadding = AppPagePadding.hv,
    this.scrollable = true,
    this.safeArea = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 构建 leading：优先用自定义 leading，其次 showBack → 标准返回按钮
    final effectiveLeading = leading ??
        (showBack
            ? Tooltip(
                message: MaterialLocalizations.of(context).backButtonTooltip,
                child: IosIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  minSize: 44, // AppBar 点击区域
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              )
            : null);

    final content = Padding(
      padding: bodyPadding,
      child: scrollable
          ? ListView(
              // 自动支持文字输入框焦点避让 + 键盘弹出时滚动
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [body],
            )
          : body,
    );

    return Scaffold(
      backgroundColor: backgroundColor ?? cs.surface,
      drawer: drawer,
      endDrawer: endDrawer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        leadingWidth: effectiveLeading != null ? 56 : null,
        leading: effectiveLeading,
        title: Text(title),
        actions: actions,
      ),
      body: safeArea ? SafeArea(child: content) : content,
      floatingActionButton: floatingActionButton,
    );
  }
}
