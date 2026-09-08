import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/palettes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/settings_ios_widgets.dart';

/// 主题设置页（动态取色 / 纯色背景 / 配色方案）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/body)，body 用 Column(stretch)
/// - padding LTRB(16,12,16,16) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md)
/// - **私有 `_TactileIconButton` → 共享 `IosIconButton`**（删除私有副本）
/// - **清理重复 import**：`provider` 与 `settings_provider` 各被导入了两次
///
/// 保留私有：`_TactileRow` / `_AnimatedPressColor`（`IosCardPress` 不回传 pressed，无法等价替换）
class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.sm, 18, AppGap.sm, 6),
          child: Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.8)),
          ),
        );

    return AppPage(
      title: l10n.displaySettingsPageThemeSettingsTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              settings.dynamicColorSupported) ...[
            header(l10n.themeSettingsPageDynamicColorSection),
            SettingsSectionCard(
              pureBackground: true,
              verticalPadding: 6,
              children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Palette,
                label: l10n.themeSettingsPageUseDynamicColorTitle,
                subtitle: l10n.themeSettingsPageUseDynamicColorSubtitle,
                value: settings.useDynamicColor,
                onChanged: (v) => context.read<SettingsProvider>().setUseDynamicColor(v),
              ),
            ]),
            const SizedBox(height: AppGap.sm),
          ],
          SettingsSectionCard(
            pureBackground: true,
            verticalPadding: 6,
            children: [
            _iosSwitchRow(
              context,
              icon: Lucide.Square,
              label: l10n.themeSettingsPageUsePureBackgroundTitle,
              subtitle: l10n.themeSettingsPageUsePureBackgroundSubtitle,
              value: settings.usePureBackground,
              onChanged: (v) => context.read<SettingsProvider>().setUsePureBackground(v),
            ),
          ]),
          const SizedBox(height: AppGap.sm),
          // header(l10n.themeSettingsPageColorPalettesSection),
          SettingsSectionCard(
            pureBackground: true,
            verticalPadding: 6,
            children: [
            for (int i = 0; i < ThemePalettes.all.length; i++) ...[
              _paletteRow(
                context,
                palette: ThemePalettes.all[i],
                selected: settings.themePaletteId == ThemePalettes.all[i].id,
                onTap: () => context.read<SettingsProvider>().setThemePalette(ThemePalettes.all[i].id),
              ),
              if (i != ThemePalettes.all.length - 1) const SettingsDivider(indent: AppGap.sm),
            ],
          ]),
        ],
      ),
    );
  }
}

// --- iOS 风格辅助组件 ---

Widget _iosSwitchRow(BuildContext context,
    {required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged}) {
  final cs = Theme.of(context).colorScheme;
  return IosTactileRow(
    onTap: () => onChanged(!value),
    builder: (ctx, pressed) {
      final baseColor = cs.onSurface.withOpacity(0.9);
      return IosPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGap.md, vertical: AppGap.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 15, color: c)),
                if (subtitle != null) ...[
                  const SizedBox(height: AppGap.xxxs),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)))
                ]
              ]),
            ),
            IosSwitch(value: value, onChanged: onChanged),
          ]),
        ),
      );
    },
  );
}

Widget _paletteRow(BuildContext context,
    {required ThemePalette palette, required bool selected, required VoidCallback onTap}) {
  final cs = Theme.of(context).colorScheme;
  final title = Localizations.localeOf(context).languageCode == 'zh'
      ? palette.displayNameZh
      : palette.displayNameEn;
  final color = palette.light.primary;
  return IosTactileRow(
    onTap: onTap,
    builder: (ctx, pressed) {
      final baseColor = cs.onSurface.withOpacity(0.9);
      return IosPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGap.xl, vertical: AppGap.sm),
          child: Row(children: [
            // 色点
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: Theme.of(context).brightness == Brightness.dark
                    ? []
                    : [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
              ),
            ),
            const SizedBox(width: AppGap.md),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15, color: c))),
            if (selected)
              Icon(Lucide.Check, size: 18, color: cs.primary)
            else
              const SizedBox(width: 18, height: 18),
          ]),
        ),
      );
    },
  );
}
