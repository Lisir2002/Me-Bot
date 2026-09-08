import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/card_surface.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/brand_assets.dart';
import '../widgets/model_select_sheet.dart';

/// 默认模型页：聊天 / 标题 / 翻译 三个模型位，每个位可选模型 + 可选提示词配置。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title / leading / actions / body)
/// - padding LTRB(16,16,16,24) → fromLTRB(AppGap.md, AppGap.md, AppGap.md, AppGap.xl)
/// - body 用 Column(crossAxisAlignment: stretch)（引擎滚动容器给紧宽度，
///   Column 默认 center 会放宽宽度导致卡片缩成内容宽度）
/// - 两个逐字重复的 showModalBottomSheet → 参数化 _showPromptSheet + AppSheet
/// - 私有 _TactileIconButton / _TactileRow → IosIconButton / IosTactileRow
class DefaultModelPage extends StatelessWidget {
  const DefaultModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    return AppPage(
      title: l10n.defaultModelPageTitle,
      leading: Tooltip(
        message: l10n.defaultModelPageBackTooltip,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      // 与原先一致：右侧留一个等宽占位，保证标题视觉居中
      actions: const [SizedBox(width: AppGap.sm)],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.md, AppGap.md, AppGap.xl),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModelCard(
            icon: Lucide.MessageCircle,
            title: l10n.defaultModelPageChatModelTitle,
            subtitle: l10n.defaultModelPageChatModelSubtitle,
            modelProvider: settings.currentModelProvider,
            modelId: settings.currentModelId,
            onPick: () async {
              final sel = await showModelSelector(context);
              if (sel != null) {
                await context.read<SettingsProvider>().setCurrentModel(sel.providerKey, sel.modelId);
              }
            },
          ),
          const SizedBox(height: AppGap.md),
          _ModelCard(
            icon: Lucide.NotebookTabs,
            title: l10n.defaultModelPageTitleModelTitle,
            subtitle: l10n.defaultModelPageTitleModelSubtitle,
            modelProvider: settings.titleModelProvider,
            modelId: settings.titleModelId,
            fallbackProvider: settings.currentModelProvider,
            fallbackModelId: settings.currentModelId,
            onPick: () async {
              final sel = await showModelSelector(context);
              if (sel != null) {
                await context.read<SettingsProvider>().setTitleModel(sel.providerKey, sel.modelId);
              }
            },
            configAction: () => _showPromptSheet(context, _PromptKind.title),
          ),
          const SizedBox(height: AppGap.md),
          _ModelCard(
            icon: Lucide.Languages,
            title: l10n.defaultModelPageTranslateModelTitle,
            subtitle: l10n.defaultModelPageTranslateModelSubtitle,
            modelProvider: settings.translateModelProvider,
            modelId: settings.translateModelId,
            fallbackProvider: settings.currentModelProvider,
            fallbackModelId: settings.currentModelId,
            onPick: () async {
              final sel = await showModelSelector(context);
              if (sel != null) {
                await context.read<SettingsProvider>().setTranslateModel(sel.providerKey, sel.modelId);
              }
            },
            configAction: () => _showPromptSheet(context, _PromptKind.translate),
          ),
        ],
      ),
    );
  }

  /// 标题 / 翻译 提示词弹层（两者结构完全一致，仅文案与读写方法不同）。
  ///
  /// 原实现是两个 110 行的 `showModalBottomSheet`，逐字重复。
  /// 现在用 AppSheet 承载（左对齐标题 + 内置拖拽把手 + footer 放操作行），
  /// 键盘避让与 SafeArea 由 `showAppSheet` 统一处理。
  Future<void> _showPromptSheet(BuildContext context, _PromptKind kind) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: kind.read(settings));

    OutlineInputBorder fieldBorder(Color color, double opacity) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color.withOpacity(opacity)),
        );

    await showAppSheet<void>(
      context: context,
      builder: AppSheet(
        title: l10n.defaultModelPagePromptLabel,
        contentPadding: const EdgeInsets.fromLTRB(AppGap.md, 4, AppGap.md, AppGap.md),
        // ignore: sort_child_properties_last —— AppSheet 语义顺序是 title → children → footer，与 lint 的「children 放最后」冲突
        children: [
          TextField(
            controller: controller,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: kind.hint(l10n),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : const Color(0xFFF2F3F5),
              border: fieldBorder(cs.outlineVariant, 0.4),
              enabledBorder: fieldBorder(cs.outlineVariant, 0.4),
              focusedBorder: fieldBorder(cs.primary, 0.5),
            ),
          ),
        ],
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    await kind.reset(settings);
                    controller.text = kind.read(settings);
                  },
                  child: Text(l10n.defaultModelPageResetDefault),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await kind.save(settings, controller.text.trim());
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(l10n.defaultModelPageSave),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              kind.vars(l10n),
              style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// 提示词弹层的两种形态，把「读 / 重置 / 保存 / 提示文案 / 变量说明」的差异收在这里。
enum _PromptKind { title, translate }

extension _PromptKindX on _PromptKind {
  String read(SettingsProvider s) =>
      this == _PromptKind.title ? s.titlePrompt : s.translatePrompt;

  String hint(AppLocalizations l10n) =>
      this == _PromptKind.title
          ? l10n.defaultModelPageTitlePromptHint
          : l10n.defaultModelPageTranslatePromptHint;

  String vars(AppLocalizations l10n) =>
      this == _PromptKind.title
          ? l10n.defaultModelPageTitleVars('{content}', '{locale}')
          : l10n.defaultModelPageTranslateVars('{source_text}', '{target_lang}');

  Future<void> reset(SettingsProvider s) =>
      this == _PromptKind.title ? s.resetTitlePrompt() : s.resetTranslatePrompt();

  Future<void> save(SettingsProvider s, String value) =>
      this == _PromptKind.title ? s.setTitlePrompt(value) : s.setTranslatePrompt(value);
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.modelProvider,
    required this.modelId,
    required this.onPick,
    this.fallbackProvider,
    this.fallbackModelId,
    this.configAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? modelProvider;
  final String? modelId;
  final String? fallbackProvider;
  final String? fallbackModelId;
  final VoidCallback onPick;
  final VoidCallback? configAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    // Check if using fallback (not explicitly set)
    final usingFallback = modelProvider == null || modelId == null;

    // Use fallback values if needed
    final effectiveProvider = modelProvider ?? fallbackProvider;
    final effectiveModelId = modelId ?? fallbackModelId;

    String? providerName;
    String? modelDisplay;
    if (effectiveProvider != null && effectiveModelId != null) {
      final cfg = settings.getProviderConfig(effectiveProvider);
      providerName = cfg.name.isNotEmpty ? cfg.name : effectiveProvider;
      final ov = cfg.modelOverrides[effectiveModelId] as Map?;
      modelDisplay = (ov != null && (ov['name'] as String?)?.isNotEmpty == true)
          ? (ov['name'] as String)
          : effectiveModelId;
    }

    // Override display text if using fallback
    if (usingFallback) {
      modelDisplay = l10n.defaultModelPageUseCurrentModel;
    }
    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: AppCardSurface.border(context),
      ),
      child: Padding(
        // 14 无精确 token（sm=12 / md=16），保留字面量
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurface),
                const SizedBox(width: AppGap.xs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                if (configAction != null)
                  IosIconButton(
                    haptics: true,
                    icon: Lucide.Settings,
                    color: cs.onSurface,
                    size: 20,
                    onTap: configAction!,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // description under title
            Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
            // 原实现是相邻两个 SizedBox(4) + SizedBox(8)，合计 12，等价于 AppGap.sm
            const SizedBox(height: AppGap.sm),
            IosTactileRow(
              onTap: onPick,
              pressedScale: 0.98,
              releaseDelay: const Duration(milliseconds: 60),
              builder: (_, pressed) {
                final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                final overlay = isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.05);
                final pressedBg = Color.alphaBlend(overlay, bg);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
                  decoration: BoxDecoration(
                    color: pressed ? pressedBg : bg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      _BrandAvatar(name: modelDisplay ?? (providerName ?? '?'), size: 24),
                      const SizedBox(width: AppGap.xs),
                      Expanded(
                        child: Text(
                          modelDisplay ?? (providerName ?? '-'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
            color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}
