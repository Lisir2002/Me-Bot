import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../../../core/services/android_background.dart';
import '../../../core/services/notification_service.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../../../core/providers/settings_provider.dart';
import 'theme_settings_page.dart';
import '../../../theme/palettes.dart';
import '../../../l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'google_fonts_picker_page.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/settings_ios_widgets.dart';

enum _FontTarget { app, code }

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    context.watch<SettingsProvider>();

    String _paletteName() {
      final settings = context.read<SettingsProvider>();
      final palette = ThemePalettes.byId(settings.themePaletteId);
      return Localizations.localeOf(context).languageCode == 'zh' ? palette.displayNameZh : palette.displayNameEn;
    }

    return AppPage(
      title: l10n.settingsPageDisplay,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      // ⚠️ scrollable 模式下子部件拿到的是「无界高度 + 紧凑宽度」，
      // 因此 Column 必须 stretch，否则卡片会缩到内容宽度。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            SettingsSectionCard(children: [
              SettingsNavRow(
                icon: Lucide.Palette,
                label: l10n.displaySettingsPageThemeSettingsTitle,
                detailText: _paletteName(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ThemeSettingsPage())),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.Languages,
                label: l10n.displaySettingsPageLanguageTitle,
                detailBuilder: (ctx) {
                  final settings = ctx.watch<SettingsProvider>();
                  String labelFor(Locale l) {
                    if (l.languageCode == 'zh') {
                      if ((l.scriptCode ?? '').toLowerCase() == 'hant') return l10n.languageDisplayTraditionalChinese;
                      return l10n.displaySettingsPageLanguageChineseLabel;
                    }
                    return l10n.displaySettingsPageLanguageEnglishLabel;
                  }
                  return Text(
                    settings.isFollowingSystemLocale ? l10n.settingsPageSystemMode : labelFor(settings.appLocale),
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                  );
                },
                onTap: () async {
                  await _showLanguageSheet(context);
                  if (mounted) setState(() {});
                },
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.MessageCircleMore,
                label: l10n.displaySettingsPageChatItemDisplayTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatItemDisplaySettingsPage())),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.TextInitial,
                label: l10n.displaySettingsPageRenderingSettingsTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RenderingSettingsPage())),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.eclipse,
                label: l10n.displaySettingsPageBehaviorStartupTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BehaviorStartupSettingsPage())),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsSettingsTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HapticsSettingsPage())),
              ),
              const SettingsDivider(),
              if (Platform.isAndroid) SettingsNavRow(
                icon: Lucide.Monitor,
                label: l10n.displaySettingsPageAndroidBackgroundChatTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  switch (sp.androidBackgroundChatMode) {
                    case AndroidBackgroundChatMode.off:
                      return Text(
                        l10n.androidBackgroundStatusOff,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                      );
                    case AndroidBackgroundChatMode.on:
                      return Text(
                        l10n.androidBackgroundStatusOn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                      );
                    case AndroidBackgroundChatMode.onNotify:
                      return Text(
                        l10n.androidBackgroundStatusOther,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                      );
                  }
                },
                onTap: () => _showAndroidBackgroundChatSheet(context),
              ),
              if (Platform.isAndroid) const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.MessageSquare,
                label: l10n.displaySettingsPageChatMessageBackgroundTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  String labelOf() {
                    switch (sp.chatMessageBackgroundStyle) {
                      case ChatMessageBackgroundStyle.frosted:
                        return l10n.displaySettingsPageChatMessageBackgroundFrosted;
                      case ChatMessageBackgroundStyle.solid:
                        return l10n.displaySettingsPageChatMessageBackgroundSolid;
                      case ChatMessageBackgroundStyle.defaultStyle:
                      default:
                        return l10n.displaySettingsPageChatMessageBackgroundDefault;
                    }
                  }
                  return Text(
                    labelOf(),
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                  );
                },
                onTap: () => _showChatMessageBackgroundSheet(context),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.Type,
                label: l10n.displaySettingsPageAppFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.appFontFamily;
                  final useLocal = (sp.appFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                          ? l10n.desktopFontFamilySystemDefault
                          : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(context, target: _FontTarget.app),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.Code,
                label: l10n.displaySettingsPageCodeFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.codeFontFamily;
                  final useLocal = (sp.codeFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                          ? l10n.desktopFontFamilyMonospaceDefault
                          : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(context, target: _FontTarget.code),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.CaseSensitive,
                label: l10n.displaySettingsPageChatFontSizeTitle,
                detailBuilder: (ctx) {
                  final scale = ctx.watch<SettingsProvider>().chatFontScale;
                  return Text('${(scale * 100).round()}%', style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13));
                },
                onTap: () => _showChatFontSizeSheet(context),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.ArrowDown,
                label: l10n.displaySettingsPageAutoScrollIdleTitle,
                detailBuilder: (ctx) {
                  final seconds = ctx.watch<SettingsProvider>().autoScrollIdleSeconds;
                  return Text('${seconds.round()}s', style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13));
                },
                onTap: () => _showAutoScrollIdleSheet(context),
              ),
              const SettingsDivider(),
              SettingsNavRow(
                icon: Lucide.Image,
                label: l10n.displaySettingsPageChatBackgroundMaskTitle,
                detailBuilder: (ctx) {
                  final v = ctx.watch<SettingsProvider>().chatBackgroundMaskStrength;
                  return Text('${(v * 100).round()}%', style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13));
                },
                onTap: () => _showChatBackgroundMaskSheet(context),
              ),
            ]),
        ],
      ),
    );
  }

  Future<void> _showMobileFontSourceSheet(BuildContext context, {required _FontTarget target}) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAppSheet<String>(
      context: context,
      isScrollControlled: false,
      builder: _OptionSheet<String>(
        options: [
          _SheetOption<String>(label: l10n.fontPickerChooseLocalFile, value: 'local'),
          _SheetOption<String>(label: l10n.fontPickerGetFromGoogleFonts, value: 'google'),
          _SheetOption<String>(label: l10n.displaySettingsPageFontResetLabel, value: 'reset'),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'local') {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['ttf', 'otf']);
      final path = res?.files.singleOrNull?.path;
      if (path == null) return;
      if (target == _FontTarget.app) {
        await context.read<SettingsProvider>().setAppFontFromLocal(path: path);
      } else {
        await context.read<SettingsProvider>().setCodeFontFromLocal(path: path);
      }
      return;
    }
    if (choice == 'google') {
      final title = target == _FontTarget.app ? l10n.displaySettingsPageAppFontTitle : l10n.displaySettingsPageCodeFontTitle;
      final selected = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => GoogleFontsPickerPage(title: title)));
      if (selected == null || selected.isEmpty) return;
      if (target == _FontTarget.app) {
        await context.read<SettingsProvider>().setAppFontFromGoogle(selected);
      } else {
        await context.read<SettingsProvider>().setCodeFontFromGoogle(selected);
      }
      return;
    }
    if (choice == 'reset') {
      if (target == _FontTarget.app) {
        await context.read<SettingsProvider>().clearAppFont();
      } else {
        await context.read<SettingsProvider>().clearCodeFont();
      }
    }
  }

  Future<void> _showChatMessageBackgroundSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAppSheet<String>(
      context: context,
      isScrollControlled: false,
      builder: _OptionSheet<String>(
        options: [
          _SheetOption<String>(label: l10n.displaySettingsPageChatMessageBackgroundDefault, value: 'default'),
          _SheetOption<String>(label: l10n.displaySettingsPageChatMessageBackgroundFrosted, value: 'frosted'),
          _SheetOption<String>(label: l10n.displaySettingsPageChatMessageBackgroundSolid, value: 'solid'),
        ],
      ),
    );
    if (choice == null) return;
    final sp = context.read<SettingsProvider>();
    switch (choice) {
      case 'frosted':
        await sp.setChatMessageBackgroundStyle(ChatMessageBackgroundStyle.frosted);
        break;
      case 'solid':
        await sp.setChatMessageBackgroundStyle(ChatMessageBackgroundStyle.solid);
        break;
      default:
        await sp.setChatMessageBackgroundStyle(ChatMessageBackgroundStyle.defaultStyle);
    }
  }

  Future<void> _showAndroidBackgroundChatSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAppSheet<String>(
      context: context,
      isScrollControlled: false,
      builder: _OptionSheet<String>(
        options: [
          _SheetOption<String>(label: l10n.androidBackgroundOptionOn, value: 'on'),
          _SheetOption<String>(label: l10n.androidBackgroundOptionOnNotify, value: 'on_notify'),
          _SheetOption<String>(label: l10n.androidBackgroundOptionOff, value: 'off'),
        ],
      ),
    );
    if (choice == null) return;
    final sp = context.read<SettingsProvider>();
    switch (choice) {
      case 'on_notify':
        await sp.setAndroidBackgroundChatMode(AndroidBackgroundChatMode.onNotify);
        try {
          await AndroidBackgroundManager.ensureInitialized(
            notificationTitle: AppLocalizations.of(context)!.androidBackgroundNotificationTitle,
            notificationText: AppLocalizations.of(context)!.androidBackgroundNotificationText,
          );
          await AndroidBackgroundManager.setEnabled(true);
          await NotificationService.ensureInitialized();
          await NotificationService.ensureAndroidNotificationsPermission();
        } catch (_) {}
        break;
      case 'on':
        await sp.setAndroidBackgroundChatMode(AndroidBackgroundChatMode.on);
        try {
          await AndroidBackgroundManager.ensureInitialized(
            notificationTitle: AppLocalizations.of(context)!.androidBackgroundNotificationTitle,
            notificationText: AppLocalizations.of(context)!.androidBackgroundNotificationText,
          );
          await AndroidBackgroundManager.setEnabled(true);
          // Prepare notification channel as well to avoid FGS notification issues on some ROMs
          await NotificationService.ensureInitialized();
        } catch (_) {}
        break;
      default:
        await sp.setAndroidBackgroundChatMode(AndroidBackgroundChatMode.off);
        try { await AndroidBackgroundManager.setEnabled(false); } catch (_) {}
    }
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAppSheet<String>(
      context: context,
      isScrollControlled: false,
      builder: _OptionSheet<String>(
        options: [
          _SheetOption<String>(label: l10n.settingsPageSystemMode, value: 'system'),
          _SheetOption<String>(label: l10n.displaySettingsPageLanguageChineseLabel, value: 'zh_CN'),
          _SheetOption<String>(label: l10n.languageDisplayTraditionalChinese, value: 'zh_Hant'),
          _SheetOption<String>(label: l10n.displaySettingsPageLanguageEnglishLabel, value: 'en_US'),
        ],
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case 'system':
        await context.read<SettingsProvider>().setAppLocaleFollowSystem();
        break;
      case 'zh_CN':
        await context.read<SettingsProvider>().setAppLocale(const Locale('zh', 'CN'));
        break;
      case 'zh_Hant':
        await context.read<SettingsProvider>().setAppLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
        break;
      case 'en_US':
      default:
        await context.read<SettingsProvider>().setAppLocale(const Locale('en', 'US'));
    }
  }

  Future<void> _showChatFontSizeSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final scale = context.watch<SettingsProvider>().chatFontScale;
        return Padding(
          // 18 无精确 token（md=16 / lg=20），保留字面量
          padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.md, AppGap.md, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('80%', style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontSize: 12)),
                const SizedBox(width: AppGap.xs),
                Expanded(
                  child: SfSliderTheme(
                    data: _sliderTheme(cs, isDark),
                    child: SfSlider(
                      value: scale,
                      min: 0.8,
                      max: 1.50001,
                      stepSize: 0.05,
                      showTicks: true,
                      showLabels: true,
                      interval: 0.1,
                      minorTicksPerInterval: 1,
                      enableTooltip: true,
                      shouldAlwaysShowTooltip: false,
                      tooltipShape: const SfPaddleTooltipShape(),
                      labelFormatterCallback: (value, text) => (value as double).toStringAsFixed(1),
                      thumbIcon: _sliderThumb(cs, isDark),
                      onChanged: (v) => context.read<SettingsProvider>().setChatFontScale((v as double).clamp(0.8, 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: AppGap.xs),
                Text('${(scale * 100).round()}%', style: TextStyle(color: cs.onSurface, fontSize: 12)),
              ]),
              const SizedBox(height: AppGap.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppGap.sm),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.displaySettingsPageChatFontSampleText,
                  style: TextStyle(fontSize: 16 * context.watch<SettingsProvider>().chatFontScale),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _showAutoScrollIdleSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final seconds = context.watch<SettingsProvider>().autoScrollIdleSeconds;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.md, AppGap.md, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('2s', style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontSize: 12)),
                const SizedBox(width: AppGap.xs),
                Expanded(
                  child: SfSliderTheme(
                    data: _sliderTheme(cs, isDark),
                    child: SfSlider(
                      value: seconds.toDouble(),
                      min: 2.0,
                      max: 64.0,
                      stepSize: 2.0,
                      showTicks: true,
                      showLabels: true,
                      interval: 10.0,
                      minorTicksPerInterval: 1,
                      enableTooltip: true,
                      shouldAlwaysShowTooltip: false,
                      tooltipShape: const SfPaddleTooltipShape(),
                      labelFormatterCallback: (value, text) => value.toInt().toString(),
                      thumbIcon: _sliderThumb(cs, isDark),
                      onChanged: (v) => context.read<SettingsProvider>().setAutoScrollIdleSeconds((v as double).round()),
                    ),
                  ),
                ),
                const SizedBox(width: AppGap.xs),
                Text('${seconds.round()}s', style: TextStyle(color: cs.onSurface, fontSize: 12)),
              ]),
              // 6 无精确 token（xxs=4 / xs=8），保留字面量
              const SizedBox(height: 6),
              Text(
                l10n.displaySettingsPageAutoScrollIdleSubtitle,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _showChatBackgroundMaskSheet(BuildContext context) async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final strength = context.watch<SettingsProvider>().chatBackgroundMaskStrength;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.md, AppGap.md, 18),
          child: Row(children: [
            Text('0%', style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontSize: 12)),
            const SizedBox(width: AppGap.xs),
            Expanded(
              child: SfSliderTheme(
                data: _sliderTheme(cs, isDark),
                child: SfSlider(
                  value: (strength * 100).roundToDouble(),
                  min: 0.0,
                  max: 200.0001,
                  stepSize: 5.0,
                  showTicks: true,
                  showLabels: true,
                  interval: 50,
                  minorTicksPerInterval: 1,
                  enableTooltip: true,
                  shouldAlwaysShowTooltip: false,
                  tooltipShape: const SfPaddleTooltipShape(),
                  labelFormatterCallback: (value, text) => '${(value as double).round()}%',
                  thumbIcon: _sliderThumb(cs, isDark),
                  onChanged: (v) => context.read<SettingsProvider>().setChatBackgroundMaskStrength(((v as double) / 100.0).clamp(0.0, 2.0)),
                ),
              ),
            ),
            const SizedBox(width: AppGap.xs),
            Text('${(strength * 100).round()}%', style: TextStyle(color: cs.onSurface, fontSize: 12)),
          ]),
        );
      }),
    );
  }
}


// ──────────────────────────────────────────────────────────────
// 本文件保留的私有组件
//
// 已迁走的（改用共享层）：
//   _iosSectionCard / _iosDivider / _iosNavRow  → settings_ios_widgets.dart
//   _TactileRow / _TactileIconButton / _AnimatedPressColor → ios_tactile.dart
//   _iosSwitchRow → 共享 AppSwitchRow（批次 4 后归并，见迁移计划「待办 E」收尾）
// 仍留在本地的（滑杆主题 / 无标题无把手的「iOS 操作表」，AppSheet 会加把手故自建）：
//   _sliderTheme / _sliderThumb / _OptionSheet / _SheetOption /
//   _SheetDividerNoIcon / _sheetOption
// ──────────────────────────────────────────────────────────────

/// 三个滑杆弹层（字号 / 自动滚动空闲 / 背景遮罩）共用的滑杆主题。
SfSliderThemeData _sliderTheme(ColorScheme cs, bool isDark) => SfSliderThemeData(
      activeTrackHeight: 8,
      inactiveTrackHeight: 8,
      overlayRadius: 14,
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
      tooltipBackgroundColor: cs.primary,
      tooltipTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
      activeTickColor: cs.onSurface.withOpacity(isDark ? 0.45 : 0.35),
      inactiveTickColor: cs.onSurface.withOpacity(isDark ? 0.30 : 0.25),
      activeMinorTickColor: cs.onSurface.withOpacity(isDark ? 0.34 : 0.28),
      inactiveMinorTickColor: cs.onSurface.withOpacity(isDark ? 0.24 : 0.20),
    );

/// 三个滑杆弹层共用的滑块圆点。
Widget _sliderThumb(ColorScheme cs, bool isDark) => Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        boxShadow: isDark
            ? []
            : [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
              ],
      ),
    );

/// 「iOS 操作表」式选项弹层：无标题、无把手、行满宽铺满。
///
/// 收敛了原先形状完全一致的四个弹层（字体来源 / 消息背景 / 安卓后台 / 语言），
/// 它们只有选项文案与回传值不同。
/// 之所以不用 `AppSheet`：AppSheet 固定带顶部把手与 `AppGap.xs` 内边距，
/// 会改变这类弹层的观感。
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({required this.options});

  final List<_SheetOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 10 无精确 token（xs=8 / sm=12），保留字面量
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i != 0) const _SheetDividerNoIcon(),
            _sheetOption(
              context,
              label: options[i].label,
              onTap: () => Navigator.of(context).pop<T>(options[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetOption<T> {
  const _SheetOption({required this.label, required this.value});
  final String label;
  final T value;
}

class _SheetDividerNoIcon extends StatelessWidget {
  const _SheetDividerNoIcon();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: AppGap.md,
      endIndent: AppGap.md,
      color: cs.outlineVariant.withOpacity(0.18),
    );
  }
}

Widget _sheetOption(BuildContext context, {required String label, required VoidCallback onTap}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return IosTactileRow(
    onTap: onTap,
    builder: (_, pressed) {
      final bgTarget = pressed
          ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
          : Colors.transparent;
      // 14 无精确 token（sm=12 / md=16），保留字面量
      return IosPressColor(
        pressed: pressed,
        base: cs.onSurface,
        builder: (c) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          color: bgTarget,
          padding: const EdgeInsets.symmetric(horizontal: AppGap.md, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
          ]),
        ),
      );
    },
  );
}


// --- Subpages ---

class ChatItemDisplaySettingsPage extends StatelessWidget {
  const ChatItemDisplaySettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
    return AppPage(
      title: l10n.displaySettingsPageChatItemDisplayTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SettingsSectionCard(children: [
          AppSwitchRow( icon: Lucide.User, label: l10n.displaySettingsPageShowUserAvatarTitle, value: sp.showUserAvatar, onChanged: (v) => context.read<SettingsProvider>().setShowUserAvatar(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.MessageCircle, label: l10n.displaySettingsPageShowUserNameTimestampTitle, value: sp.showUserNameTimestamp, onChanged: (v) => context.read<SettingsProvider>().setShowUserNameTimestamp(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Ellipsis, label: l10n.displaySettingsPageShowUserMessageActionsTitle, value: sp.showUserMessageActions, onChanged: (v) => context.read<SettingsProvider>().setShowUserMessageActions(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Bot, label: l10n.displaySettingsPageChatModelIconTitle, value: sp.showModelIcon, onChanged: (v) => context.read<SettingsProvider>().setShowModelIcon(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.MessageSquare, label: l10n.displaySettingsPageShowModelNameTimestampTitle, value: sp.showModelNameTimestamp, onChanged: (v) => context.read<SettingsProvider>().setShowModelNameTimestamp(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Type, label: l10n.displaySettingsPageShowTokenStatsTitle, value: sp.showTokenStats, onChanged: (v) => context.read<SettingsProvider>().setShowTokenStats(v)),
        ]),
      ]),
    );
  }
}

class RenderingSettingsPage extends StatelessWidget {
  const RenderingSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final l10n = AppLocalizations.of(context)!; final sp = context.watch<SettingsProvider>();
    return AppPage(
      title: l10n.displaySettingsPageRenderingSettingsTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SettingsSectionCard(children: [
          AppSwitchRow( icon: Lucide.Hash, label: l10n.displaySettingsPageEnableDollarLatexTitle, value: sp.enableDollarLatex, onChanged: (v) => context.read<SettingsProvider>().setEnableDollarLatex(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Code, label: l10n.displaySettingsPageEnableMathTitle, value: sp.enableMathRendering, onChanged: (v) => context.read<SettingsProvider>().setEnableMathRendering(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.TextSelect, label: l10n.displaySettingsPageEnableUserMarkdownTitle, value: sp.enableUserMarkdown, onChanged: (v) => context.read<SettingsProvider>().setEnableUserMarkdown(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Brain, label: l10n.displaySettingsPageEnableReasoningMarkdownTitle, value: sp.enableReasoningMarkdown, onChanged: (v) => context.read<SettingsProvider>().setEnableReasoningMarkdown(v)),
        ]),
      ]),
    );
  }
}

class BehaviorStartupSettingsPage extends StatelessWidget {
  const BehaviorStartupSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final l10n = AppLocalizations.of(context)!; final sp = context.watch<SettingsProvider>();
    return AppPage(
      title: l10n.displaySettingsPageBehaviorStartupTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SettingsSectionCard(children: [
          AppSwitchRow( icon: Lucide.Brain, label: l10n.displaySettingsPageAutoCollapseThinkingTitle, value: sp.autoCollapseThinking, onChanged: (v) => context.read<SettingsProvider>().setAutoCollapseThinking(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.BadgeInfo, label: l10n.displaySettingsPageShowUpdatesTitle, value: sp.showAppUpdates, onChanged: (v) => context.read<SettingsProvider>().setShowAppUpdates(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.ChevronRight, label: l10n.displaySettingsPageMessageNavButtonsTitle, value: sp.showMessageNavButtons, onChanged: (v) => context.read<SettingsProvider>().setShowMessageNavButtons(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Calendar, label: l10n.displaySettingsPageShowChatListDateTitle, value: sp.showChatListDate, onChanged: (v) => context.read<SettingsProvider>().setShowChatListDate(v)),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.MessageCirclePlus, label: l10n.displaySettingsPageNewChatOnLaunchTitle, value: sp.newChatOnLaunch, onChanged: (v) => context.read<SettingsProvider>().setNewChatOnLaunch(v)),
        ]),
      ]),
    );
  }
}

class HapticsSettingsPage extends StatelessWidget {
  const HapticsSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final l10n = AppLocalizations.of(context)!; final sp = context.watch<SettingsProvider>();
    return AppPage(
      title: l10n.displaySettingsPageHapticsSettingsTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SettingsSectionCard(children: [
          AppSwitchRow(
            icon: Lucide.Vibrate,
            label: l10n.displaySettingsPageHapticsGlobalTitle,
            value: sp.hapticsGlobalEnabled,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsGlobalEnabled(v),
          ),
          const SettingsDivider(),
          AppSwitchRow(
            icon: Lucide.toggleRight,
            label: l10n.displaySettingsPageHapticsIosSwitchTitle,
            value: sp.hapticsIosSwitch,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsIosSwitch(v),
          ),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.panelRight, label: l10n.displaySettingsPageHapticsOnSidebarTitle, value: sp.hapticsOnDrawer, onChanged: (v) => context.read<SettingsProvider>().setHapticsOnDrawer(v)),
          const SettingsDivider(),
          AppSwitchRow(
            icon: Lucide.ListOrdered,
            label: l10n.displaySettingsPageHapticsOnListItemTapTitle,
            value: sp.hapticsOnListItemTap,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsOnListItemTap(v),
          ),
          const SettingsDivider(),
          AppSwitchRow(
            icon: Lucide.Square,
            label: l10n.displaySettingsPageHapticsOnCardTapTitle,
            value: sp.hapticsOnCardTap,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsOnCardTap(v),
          ),
          const SettingsDivider(),
          AppSwitchRow( icon: Lucide.Vibrate, label: l10n.displaySettingsPageHapticsOnGenerateTitle, value: sp.hapticsOnGenerate, onChanged: (v) => context.read<SettingsProvider>().setHapticsOnGenerate(v)),
        ]),
      ]),
    );
  }
}
