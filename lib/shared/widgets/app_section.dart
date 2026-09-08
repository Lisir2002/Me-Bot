import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../icons/lucide_adapter.dart';
import '../../theme/design_tokens.dart';
import 'card_surface.dart';
import 'ios_switch.dart';
import 'ios_tactile.dart';

// ──────────────────────────────────────────────────────────────
// iOS 风格「分组卡 + 分隔线 + 导航行」三件套（**shared 层**）
//
// 来历：这四个组件原本是 `settings` 家族的私有件（`_iosSectionCard` /
// `_iosDivider` / `_iosNavRow` / `_iosNavRowSvgLeading`），在 `about` /
// `sponsor` / `theme_settings` / `default_model` / `display_settings` 里
// 逐字重复了 5 份。批次 3 提取到 `features/settings/widgets/settings_ios_widgets.dart`。
//
// 批次 4 时发现 **provider / backup 两个 feature 也各有一份逐值相同的副本**，
// 而它们不该反向依赖 `features/settings`（虽然本仓库已有
// `provider → model`、`backup → storage` 的先例，但方向越多越难维护）。
// 全仓统计 `_iosSectionCard` 有 12 份副本，故**再往上提一层到 shared**，
// 让 settings / storage / provider / backup 四方都依赖 shared。
//
// 差异用参数表达：
//   AppSectionCard.pureBackground —— 跟随「纯色背景」开关（仅 theme_settings 用）
//   AppSectionCard.verticalPadding —— theme_settings 是 6，其余是 AppGap.xxs(4)
//   AppSectionDivider.indent      —— 默认 54（对齐图标列），theme_settings 传 12
//   AppNavRow.icon / svgAsset     —— 图标或 SVG 二选一
//   AppNavRow.haptics             —— 默认 true（theme/default_model/display/backup
//                                    一致），about / sponsor 显式传 false
//
// AppSwitchRow 来历（原「待办 E」）：`display_settings` / `backup` /
// `provider_detail` / `assistant_settings_edit` / `mcp_server_edit_sheet` /
// `add_provider_sheet` 等 8 处逐值相同的 `_iosSwitchRow`。
// 批次 4 迁 `backup_page` 时提取，后续页面直接复用。
//
// ⚠️ 与 `storage_ios_widgets.dart` 的关系：storage 那份依赖 storage 私有的
// `storageCardBackground` / `storageCardBorder`，暂时留在 features 层。
// 待 storage 也迁到本文件后，`storage_ios_widgets.dart` 可整体删除。
// ──────────────────────────────────────────────────────────────

/// iOS 风格分组卡片容器。
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.children,
    this.pureBackground = false,
    this.verticalPadding = AppGap.xxs,
  });

  final List<Widget> children;

  /// 是否跟随「设置 → 纯色背景」开关（深色纯黑 / 浅色纯白）。
  /// 只有本身就在展示背景设置的页面（`theme_settings`）需要开。
  final bool pureBackground;

  /// 卡片内部纵向留白。默认 `AppGap.xxs`(4)，`theme_settings` 传 6。
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 短路：pureBackground 为 false 时不订阅 SettingsProvider，避免无谓重建。
    final bool pure = pureBackground
        ? context.select<SettingsProvider, bool>((s) => s.usePureBackground)
        : false;
    final Color bg = pure
        ? (isDark ? Colors.black : const Color(0xFFFFFFFF))
        : (isDark ? Colors.white10 : Colors.white.withOpacity(0.96));
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: AppCardSurface.border(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Column(children: children),
      ),
    );
  }
}

/// 行间分隔线（默认与 36 宽的图标列对齐）。
class AppSectionDivider extends StatelessWidget {
  const AppSectionDivider({
    super.key,
    this.indent = 54,
    this.endIndent = AppGap.sm,
  });

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // height 6 无精确 token（xxs=4 / xs=8），保留字面量
    return Divider(
      height: 6,
      thickness: 0.6,
      indent: indent,
      endIndent: endIndent,
      color: cs.outlineVariant.withOpacity(0.18),
    );
  }
}

/// iOS 风格导航行：图标 + 标签 + 可选详情 + 可选右箭头。
///
/// 按压时只做颜色位移，不缩放。传 `onTap` 即视为可交互，会显示右箭头。
class AppNavRow extends StatelessWidget {
  const AppNavRow({
    super.key,
    this.icon,
    this.svgAsset,
    required this.label,
    this.onTap,
    this.detailText,
    this.detailBuilder,
    this.haptics = true,
  }) : assert(icon != null || svgAsset != null, 'icon 或 svgAsset 至少提供一个');

  /// 前置图标（Lucide）。
  final IconData? icon;

  /// 前置 SVG 资源路径（与 [icon] 二选一）。
  final String? svgAsset;

  final String label;
  final VoidCallback? onTap;
  final String? detailText;
  final Widget Function(BuildContext ctx)? detailBuilder;

  /// 点按时是否给软触觉。
  ///
  /// 默认 `true` —— 与原 `theme_settings` / `default_model` / `display_settings`
  /// / `backup` 的私有实现一致；`about` / `sponsor` 显式传 `false`。
  /// 最终仍受「设置 → 列表项点按触觉」开关约束（见 `IosTactileRow`）。
  final bool haptics;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final interactive = onTap != null;
    return IosTactileRow(
      onTap: onTap,
      haptics: haptics,
      builder: (ctx, pressed) {
        final baseColor = cs.onSurface.withOpacity(0.9);
        return IosPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (c) => Padding(
            // 11 无精确 token（sm=12 会偏大），保留字面量
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: svgAsset != null
                      ? SvgPicture.asset(
                          svgAsset!,
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                        )
                      : Icon(icon, size: 20, color: c),
                ),
                const SizedBox(width: AppGap.sm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle(
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                      child: detailBuilder!(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText!,
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// iOS 风格开关行：图标 + 标签 + `IosSwitch`。整行可点（切换开关）。
///
/// 按压时只做颜色位移，**不缩放**——与 `AppNavRow` 保持一致。
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    this.icon,
    this.svgAsset,
    required this.label,
    required this.value,
    required this.onChanged,
    this.haptics = true,
  }) : assert(icon != null || svgAsset != null, 'icon 或 svgAsset 至少提供一个');

  final IconData? icon;
  final String? svgAsset;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 见 [AppNavRow.haptics]。
  final bool haptics;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosTactileRow(
      onTap: () => onChanged(!value),
      haptics: haptics,
      builder: (ctx, pressed) {
        final baseColor = cs.onSurface.withOpacity(0.9);
        return IosPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (c) => Padding(
            // 2 无精确 token，保留字面量
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 2),
            child: Row(
              children: [
                if (icon != null) ...[
                  SizedBox(
                    width: 36,
                    child: Icon(icon, size: 20, color: c),
                  ),
                  const SizedBox(width: AppGap.sm),
                ] else if (svgAsset != null) ...[
                  SizedBox(
                    width: 36,
                    child: SvgPicture.asset(
                      svgAsset!,
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(width: AppGap.sm),
                ],
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
                IosSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        );
      },
    );
  }
}
