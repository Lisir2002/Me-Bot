import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../model/pages/default_model_page.dart';
import '../../provider/pages/providers_page.dart';
import 'display_settings_page.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../shared/widgets/card_surface.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import 'about_page.dart';
import 'tts_services_page.dart';
import 'sponsor_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../backup/pages/backup_page.dart';
import '../../storage/pages/storage_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import 'network_proxy_page.dart';
import 'usage_stats_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../theme/design_tokens.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    String modeLabel(ThemeMode m) {
      switch (m) {
        case ThemeMode.dark:
          return l10n.settingsPageDarkMode;
        case ThemeMode.light:
          return l10n.settingsPageLightMode;
        case ThemeMode.system:
        default:
          return l10n.settingsPageSystemMode;
      }
    }

    Future<void> pickThemeMode() async {
      final selected = await showModalBottomSheet<ThemeMode>(
        context: context,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetOption(
                    ctx,
                    icon: Lucide.Monitor,
                    label: modeLabel(ThemeMode.system),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.system),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Sun,
                    label: modeLabel(ThemeMode.light),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.light),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Moon,
                    label: modeLabel(ThemeMode.dark),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (selected != null) {
        await context.read<SettingsProvider>().setThemeMode(selected);
      }
    }

    // iOS-style section header (neutral color, not theme color)
    Widget header(String text, {bool first = false}) => Padding(
          padding: EdgeInsets.fromLTRB(12, first ? 2 : 12, 12, 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        );

    return AppPage(
      title: l10n.settingsPageTitle,
      // 用自定义 leading 保留原来的 Tooltip 文案（AppPage 默认用系统 backButtonTooltip）
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!settings.hasAnyActiveModel)
            Material(
              color: cs.errorContainer.withOpacity(0.30),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Lucide.MessageCircleWarning, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.settingsPageWarningMessage,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 通用设置：使用iOS风格分组卡片，黑色（中性）图标与标题，无描述
          header(l10n.settingsPageGeneralSection, first: true),
          _iosSectionCard(children: [
            _iosNavRow(
              context,
              icon: Lucide.SunMoon,
              label: l10n.settingsPageColorMode,
              detailText: modeLabel(settings.themeMode),
              onTap: pickThemeMode,
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Monitor,
              label: l10n.settingsPageDisplay,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DisplaySettingsPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Bot,
              label: l10n.settingsPageAssistant,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AssistantSettingsPage()),
                );
              },
            ),
          ]),

          const SizedBox(height: 12),
          header(l10n.settingsPageModelsServicesSection),
          _iosSectionCard(children: [
            _iosNavRow(
              context,
              icon: Lucide.Heart,
              label: l10n.settingsPageDefaultModel,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DefaultModelPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Boxes,
              label: l10n.settingsPageProviders,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProvidersPage()));
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Earth,
              label: l10n.settingsPageSearch,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchServicesPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Volume2,
              label: l10n.settingsPageTts,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TtsServicesPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Terminal,
              label: l10n.settingsPageMcp,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const McpPage()));
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Zap,
              label: l10n.settingsPageQuickPhrase,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuickPhrasesPage()));
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.EthernetPort,
              label: l10n.settingsPageNetworkProxy,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NetworkProxyPage()),
                );
              },
            ),
          ]),

          const SizedBox(height: 12),
          header(l10n.settingsPageDataSection),
          _iosSectionCard(children: [
            _iosNavRow(
              context,
              icon: Lucide.Activity,
              label: l10n.settingsPageStats,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsageStatsPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Database,
              label: l10n.settingsPageBackup,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BackupPage()),
                );
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.HardDrive,
              label: l10n.settingsPageChatStorage,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StoragePage()),
                );
              },
            ),
          ]),

          const SizedBox(height: 12),
          header(l10n.settingsPageAboutSection),
          _iosSectionCard(children: [
            _iosNavRow(
              context,
              icon: Lucide.BadgeInfo,
              label: l10n.settingsPageAbout,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Library,
              label: l10n.settingsPageDocs,
              onTap: () async {
                final uri = Uri.parse('https://minime-core.psycheas.top/');
                if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            _iosDivider(context),
            _iosNavRow(
              context,
              icon: Lucide.Heart,
              label: l10n.settingsPageSponsor,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SponsorPage()),
                );
              },
            ),
            // _iosDivider(context),
            // _iosNavRow(
            //   context,
            //   icon: Lucide.Share2,
            //   label: l10n.settingsPageShare,
            //   onTap: () async {
            //     // Provide anchor rect from overlay for iPad share sheet
            //     Rect anchor;
            //     try {
            //       final overlay = Overlay.of(context);
            //       final ro = overlay?.context.findRenderObject();
            //       if (ro is RenderBox && ro.hasSize) {
            //         final center = ro.size.center(Offset.zero);
            //         final global = ro.localToGlobal(center);
            //         anchor = Rect.fromCenter(center: global, width: 1, height: 1);
            //       } else {
            //         final size = MediaQuery.of(context).size;
            //         anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
            //       }
            //     } catch (_) {
            //       final size = MediaQuery.of(context).size;
            //       anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
            //     }
            //     await Share.share(l10n.settingsShare, sharePositionOrigin: anchor);
            //   },
            // ),
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(builder: (context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Light: white with slight transparency; Dark: subtle translucent dark
    final Color bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        // 统一细黑边规范
        border: AppCardSurface.border(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  });
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  // Restore previous visual: align with icon slot (36) + gap (12) + padding (12)
  return Divider(height: 6, thickness: 0.6, indent: 54, endIndent: 12, color: cs.outlineVariant.withOpacity(0.18));
}

// Shared color tween wrapper to mimic iOS gentle press color transition
class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({required this.pressed, required this.base, required this.builder});
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 1.00,
    haptics: false,
    builder: (pressed) {
      final baseColor = cs.onSurface.withOpacity(0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(detailText, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap, this.pressedScale = 1.00, this.haptics = true});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics && context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}

// Bottom sheet iOS-style option with tactile feedback (no ripple)
Widget _sheetOption(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _TactileRow(
    pressedScale: 1.00,
    haptics: true,
    onTap: onTap,
    builder: (pressed) {
      final base = cs.onSurface;
      final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
      final bgTarget = pressed
          ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
          : Colors.transparent;
      return _AnimatedPressColor(
        pressed: pressed,
        base: base,
        builder: (c) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(width: 24, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 1, thickness: 0.6, indent: 52, endIndent: 16, color: cs.outlineVariant.withOpacity(0.18));
}
