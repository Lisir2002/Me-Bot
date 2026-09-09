import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../icons/lucide_adapter.dart';
import 'package:haptic_feedback/haptic_feedback.dart' as HF;
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/settings_ios_widgets.dart';

/// 关于页：应用信息卡 + 链接列表 + 版本号连点 7 次的彩蛋测试面板。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/body)，body 用 Column(stretch)
/// - padding LTRB(16,20,16,16) → fromLTRB(AppGap.md, AppGap.lg, AppGap.md, AppGap.md)
/// - **私有 `_TactileIconButton` → 共享 `IosIconButton`**
/// - **私有 `_TactileRow` / `_AnimatedPressColor` → 共享 `IosTactileRow` + `IosPressColor`**
///
/// 彩蛋弹层**保持自建**：`FractionallySizedBox(0.7) + StatefulBuilder + 内部滚动 + Expanded`
/// 属于 AppSheet 明示不适用的复杂弹层（内部滚动的定高面板 + 居中关闭按钮），不强行套模板。
///
/// iOS 风格行/卡已收敛到共享组件（[收尾代办 C]）：
/// `_iosSectionCard` / `_iosDivider` / `_iosNavRow` / `_iosNavRowSvgLeading`
/// → `SettingsSectionCard` / `SettingsDivider` / `SettingsNavRow`
/// （见 `../widgets/settings_ios_widgets.dart`）。仍保留私有的只有 `_TestButton`。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';
  String _systemInfo = '';
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final pkg = await PackageInfo.fromPlatform();
    String sys;
    if (Platform.isAndroid) {
      sys = 'Android';
    } else if (Platform.isIOS) {
      sys = 'iOS';
    } else if (Platform.isMacOS) {
      sys = 'macOS';
    } else if (Platform.isWindows) {
      sys = 'Windows';
    } else if (Platform.isLinux) {
      sys = 'Linux';
    } else {
      sys = Platform.operatingSystem;
    }
    setState(() {
      _version = pkg.version;
      _buildNumber = pkg.buildNumber;
      _systemInfo = sys;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback: try in-app web view
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  void _onVersionTap() {
    final now = DateTime.now();
    // Reset the counter if taps are spaced too far apart
    if (_lastVersionTap == null || now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;

    const threshold = 7;
    if (_versionTapCount < threshold) return;

    _versionTapCount = 0; // reset after unlock
    _showEasterEgg();
  }

  void _showEasterEgg() {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width,
        maxWidth: MediaQuery.of(context).size.width,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        // Local state for preview controls inside the sheet
        bool iosSwitchValue = false;
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            int testCounter = 0;

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.7,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.md, AppGap.md, AppGap.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Lucide.Sparkles, size: 28, color: cs.primary),
                      const SizedBox(height: 10),
                      Text(
                        l10n.aboutPageEasterEggTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppGap.xs),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Text(
                                l10n.aboutPageEasterEggMessage,
                                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.75), height: 1.3),
                              ),
                              const SizedBox(height: AppGap.xl),
                              const Divider(),
                              const SizedBox(height: AppGap.md),
                              Text(
                                'Toast Notification Test Area',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppGap.md),
                              Wrap(
                                spacing: AppGap.xs,
                                runSpacing: AppGap.xs,
                                alignment: WrapAlignment.center,
                                children: [
                                  _TestButton(
                                    label: 'Success',
                                    color: const Color(0xFF34C759),
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'Operation completed successfully! #$testCounter',
                                        type: NotificationType.success,
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Error',
                                    color: const Color(0xFFFF3B30),
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'An error occurred. Please try again. #$testCounter',
                                        type: NotificationType.error,
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Warning',
                                    color: const Color(0xFFFF9500),
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'Warning: Low battery detected #$testCounter',
                                        type: NotificationType.warning,
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Info',
                                    color: cs.primary,
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'New message received #$testCounter',
                                        type: NotificationType.info,
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'With Action',
                                    color: cs.secondary,
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'File downloaded #$testCounter',
                                        type: NotificationType.success,
                                        actionLabel: 'Open',
                                        onAction: () {
                                          showAppSnackBar(
                                            context,
                                            message: 'Opening file...',
                                            type: NotificationType.info,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Long Message',
                                    color: cs.tertiary,
                                    onTap: () {
                                      testCounter++;
                                      showAppSnackBar(
                                        context,
                                        message: 'This is a very long message that demonstrates how the toast notification handles multiline text gracefully #$testCounter',
                                        type: NotificationType.info,
                                        duration: const Duration(seconds: 5),
                                      );
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Quick Burst',
                                    color: cs.onSurface.withValues(alpha: 0.7),
                                    onTap: () {
                                      for (int i = 0; i < 5; i++) {
                                        Future.delayed(Duration(milliseconds: i * 100), () {
                                          if (mounted) {
                                            showAppSnackBar(
                                              context,
                                              message: 'Rapid notification ${i + 1}',
                                              type: NotificationType.info,
                                              duration: const Duration(seconds: 2),
                                            );
                                          }
                                        });
                                      }
                                    },
                                  ),
                                  _TestButton(
                                    label: 'Dismiss All',
                                    color: cs.error,
                                    onTap: () {
                                      AppSnackBarManager().dismissAll();
                                    },
                                  ),
                                ],
                              ),
                              // Removed vibration/flutter_vibrate sections.
                              const SizedBox(height: AppGap.xl),
                              const Divider(),
                              const SizedBox(height: AppGap.md),
                              Text(
                                'Haptic Feedback (Plugin) Test',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppGap.sm),
                              Wrap(
                                spacing: AppGap.xs,
                                runSpacing: AppGap.xs,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final e in [
                                    ['success', HF.HapticsType.success],
                                    ['warning', HF.HapticsType.warning],
                                    ['error', HF.HapticsType.error],
                                    ['light', HF.HapticsType.light],
                                    ['medium', HF.HapticsType.medium],
                                    ['heavy', HF.HapticsType.heavy],
                                    ['rigid', HF.HapticsType.rigid],
                                    ['soft', HF.HapticsType.soft],
                                    ['selection', HF.HapticsType.selection],
                                  ])
                                    _TestButton(
                                      label: e[0] as String,
                                      color: cs.primary,
                                      onTap: () async {
                                        if (!context.read<SettingsProvider>().hapticsGlobalEnabled) return;
                                        try {
                                          final can = await HF.Haptics.canVibrate();
                                          if (can) {
                                            await HF.Haptics.vibrate(e[1] as HF.HapticsType);
                                          }
                                        } catch (_) {}
                                      },
                                    ),
                                  _TestButton(
                                    label: 'Play All',
                                    color: cs.secondary,
                                    onTap: () async {
                                      if (!context.read<SettingsProvider>().hapticsGlobalEnabled) return;
                                      try {
                                        final can = await HF.Haptics.canVibrate();
                                        if (!can) return;
                                        final types = <HF.HapticsType>[
                                          HF.HapticsType.success,
                                          HF.HapticsType.warning,
                                          HF.HapticsType.error,
                                          HF.HapticsType.light,
                                          HF.HapticsType.medium,
                                          HF.HapticsType.heavy,
                                          HF.HapticsType.rigid,
                                          HF.HapticsType.soft,
                                          HF.HapticsType.selection,
                                        ];
                                        for (final t in types) {
                                          await HF.Haptics.vibrate(t);
                                          await Future.delayed(const Duration(milliseconds: 180));
                                        }
                                      } catch (_) {}
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppGap.xl),
                              const Divider(),
                              const SizedBox(height: AppGap.md),
                              Text(
                                'Custom Switch Preview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppGap.sm),
                              Material(
                                color: Colors.transparent,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: AppGap.xxs, vertical: 6),
                                  child: Row(
                                    children: [
                                      Text(
                                        'iOS‑style switch',
                                        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.9)),
                                      ),
                                      const Spacer(),
                                      IosSwitch(
                                        value: iosSwitchValue,
                                        onChanged: (v) => dialogSetState(() => iosSwitchValue = v),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppGap.sm),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        child: Text(l10n.aboutPageEasterEggButton),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AppPage(
      title: l10n.settingsPageAbout,
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
      actions: const [SizedBox(width: AppGap.sm)],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.lg, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部卡：左图标 + 右标题/描述
          SettingsSectionCard(children: [
            Padding(
              // 10 无精确 token
              padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: AppGap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MiniMe-Core',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppGap.xxs),
                        Text(
                          l10n.aboutPageAppDescription,
                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.65), height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: AppGap.sm),

          // iOS 风格列表卡
          SettingsSectionCard(children: [
            // 版本号（连点 7 次解锁彩蛋）— 逻辑不变
            SettingsNavRow(
              haptics: false,              icon: Lucide.Code,
              label: l10n.aboutPageVersion,
              detailBuilder: (_) => Text(_version.isEmpty ? '...' : '$_version / $_buildNumber'),
              onTap: _onVersionTap,
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              icon: Lucide.Phone,
              label: l10n.aboutPageSystem,
              detailBuilder: (_) => Text(_systemInfo.isEmpty ? '...' : _systemInfo),
              onTap: null, // 仅展示
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              icon: Lucide.Earth,
              label: l10n.aboutPageWebsite,
              onTap: () async {
                final uri = Uri.parse('https://minime-core.psycheas.top/');
                if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              icon: Lucide.Github,
              label: 'GitHub',
              onTap: () => _openUrl('https://github.com/Chevey339/minime-core'),
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              icon: Lucide.FileText,
              label: l10n.aboutPageLicense,
              onTap: () => _openUrl('https://github.com/Chevey339/minime-core/blob/master/LICENSE'),
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              svgAsset: 'assets/icons/tencent-qq.svg',
              label: l10n.aboutPageJoinQQGroup,
              onTap: () => _openUrl('https://qm.qq.com/q/OQaXetKssC'),
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              svgAsset: 'assets/icons/discord.svg',
              label: l10n.aboutPageJoinDiscord,
              onTap: () => _openUrl('https://discord.gg/Tb8DyvvV5T'),
            ),
          ]),

          const SizedBox(height: AppGap.xl),
        ],
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withValues(alpha: isDark ? 0.2 : 0.1),
      // 10 无精确 token（AppRadius.sm=8 / md=12），保留字面量
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xs),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? color : color.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}
