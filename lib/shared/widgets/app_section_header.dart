import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

// ──────────────────────────────────────────────────────────────
// 统一标题组件体系
//
// 来历：全仓至少有 8 份手写的页面级 section header（backup / mcp / search /
// settings / sponsor / theme_settings / tts_services / SecuritySectionHeader /
// StorageSectionHeader），边距各不相同（top 有 0/2/6/12/14/18/20 七种写法，
// bottom 有 4/6/8 三种），且 AppSectionCard 内部 Column 默认
// crossAxisAlignment: center，裸 Padding+Text 会居中。
//
// 本文件提供四个统一组件，禁止页面再手写 Padding+Text 标题：
//   AppSectionHeader —— 页面级分组标题（卡片之间），13px w600
//   AppSectionDesc   —— 页面级分组描述，紧跟标题下方，12px 弱化
//   AppCardHeader    —— 卡内分组标题，13px w600，可选 trailing
//   AppCardDesc      —— 卡内描述 / 空态文案，12px 弱化
//
// 所有组件内部用 SizedBox(width: double.infinity) 占满整行，
// 即使父级 Column 未 stretch 也能保证左对齐。
// ──────────────────────────────────────────────────────────────

/// 页面级分组标题（位于 AppSectionCard 之间）。
///
/// 视觉规范：13px / w600 / onSurface 80% 透明度。
/// 边距：左右 12，首个标题顶部 2、后续标题顶部 18，底部 6。
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(
    this.text, {
    super.key,
    this.first = false,
    this.icon,
    this.iconColor,
  });

  final String text;

  /// 是否为页面第一个标题：首个标题顶部留白更小（2 vs 18）。
  final bool first;

  /// 可选前置图标（如 MCP 页的分组图标）。
  final IconData? icon;

  /// 前置图标颜色，默认与文字同色。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurface.withValues(alpha: 0.8);
    return SizedBox(
      width: double.infinity,
      child: Padding(
        // 18 / 6 无精确 token（lg=20 / xs=8），保留字面量
        padding: EdgeInsets.fromLTRB(
            AppGap.sm, first ? AppGap.xxxs : 18, AppGap.sm, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor ?? color),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面级分组描述（紧跟 [AppSectionHeader] 下方）。
///
/// 视觉规范：12px / onSurface 55% 透明度。
/// 边距：左右 12，底部 12（与下方卡片拉开距离）。
class AppSectionDesc extends StatelessWidget {
  const AppSectionDesc(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.sm),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

/// 卡内分组标题（位于 AppSectionCard / StorageSectionCard 内部）。
///
/// 视觉规范：13px / w600 / onSurface 90% 透明度。
/// 边距：左右 12，上下 4。
/// 用 Row+Expanded 占满整行，可选右侧操作区（trailing）。
///
/// 替代原 SecurityRowHeader（15px），统一为 13px w600。
class AppCardHeader extends StatelessWidget {
  const AppCardHeader(
    this.text, {
    super.key,
    this.trailing,
  });

  final String text;

  /// 右侧操作区，如「恢复默认」「添加」按钮。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 卡内描述 / 空态文案（位于 AppSectionCard 内部）。
///
/// 视觉规范：12px / onSurface 55% 透明度。
/// 边距：左右 12，底部 4。
class AppCardDesc extends StatelessWidget {
  const AppCardDesc(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.xxs),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
