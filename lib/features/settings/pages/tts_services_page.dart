import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/tts/network_tts.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section_header.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/brand_assets.dart';
import '../widgets/settings_ios_widgets.dart';

/// TTS 服务页：系统 TTS 行 + 网络 TTS 列表（选择 / 试听 / 配置 / 删除）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title / leading / actions / body)
/// - padding LTRB(16,12,16,24) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl)
/// - body 用 Column(crossAxisAlignment: stretch)（引擎滚动容器给紧宽度）
/// - `_iosSectionCard` / `_iosDivider` → 共享 `SettingsSectionCard` / `SettingsDivider`
/// - `_TactileIconButton` → `IosIconButton(haptics: true)`；
///   `_TactileRow` / `_AnimatedPressColor` → `IosTactileRow` / `IosPressColor`
/// - 4 个弹层分别收敛：错误详情 / 系统配置 → `AppSheet`；
///   新增·编辑表单 → `showAppSheet`（居中标题 + 左右图标头，故内容自建）
class TtsServicesPage extends StatelessWidget {
  const TtsServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AppPage(
      title: l10n.ttsServicesPageTitle,
      leading: Tooltip(
        message: l10n.ttsServicesPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Tooltip(
          message: l10n.ttsServicesPageAddTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            onTap: () async {
              final created = await _showAddNetworkTtsSheet(context);
              if (created != null) {
                final sp = context.read<SettingsProvider>();
                final list = List<TtsServiceOptions>.from(sp.ttsServices)..add(created);
                await sp.setTtsServices(list);
                if (sp.usingSystemTts) {
                  await sp.setTtsServiceSelected(list.length - 1);
                }
              }
            },
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl),
      body: Consumer2<TtsProvider, SettingsProvider>(
        builder: (context, tts, sp, _) {
          final services = sp.ttsServices;
          final available = tts.isAvailable && (tts.error == null);
          final titleText = l10n.ttsServicesPageSystemTtsTitle;
          final subText = available
              ? l10n.ttsServicesPageSystemTtsAvailableSubtitle
              : l10n.ttsServicesPageSystemTtsUnavailableSubtitle(tts.error ??
                  l10n.ttsServicesPageSystemTtsUnavailableNotInitialized);
          final systemLetter = (titleText.trim().isEmpty
                  ? '?'
                  : titleText.trim().substring(0, 1))
              .toUpperCase();
          // crossAxisAlignment.stretch 必需：引擎滚动容器给子项紧宽度
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionHeader(l10n.ttsServicesPageTitle, first: true),
              SettingsSectionCard(children: [                // System TTS as first row
                IosTactileRow(
                  pressedScale: 0.98,
                  haptics: false,
                  onTap: available
                      ? () async {
                          try {
                            await sp.setTtsServiceSelected(-1);
                          } catch (_) {}
                        }
                      : null,
                  builder: (_, pressed) {
                    final cs2 = Theme.of(context).colorScheme;
                    final base = cs2.onSurface.withOpacity(0.9);
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    final overlay = pressed
                        ? (isDark
                            ? Colors.black.withOpacity(0.06)
                            : Colors.white.withOpacity(0.05))
                        : Colors.transparent;
                    return IosPressColor(
                      pressed: pressed,
                      base: base,
                      builder: (c) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppGap.sm, vertical: 11),
                          child: Row(
                            children: [
                              _AvatarBadge(letter: systemLetter, overlay: overlay),
                              const SizedBox(width: AppGap.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(titleText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 15,
                                            color: c,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(subText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12, color: c.withOpacity(0.7))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppGap.xs),
                              _SmallTactileIcon(
                                icon: Lucide.Volume2,
                                baseColor: c,
                                onTap: available
                                    ? () async {
                                        final demo = l10n.ttsServicesPageTestSpeechText;
                                        await tts.speakSystem(demo);
                                      }
                                    : () {},
                                enabled: available,
                              ),
                              const SizedBox(width: 6),
                              _SmallTactileIcon(
                                icon: Lucide.Settings2,
                                baseColor: c,
                                onTap: available
                                    ? () => _showSystemTtsConfig(context)
                                    : () {},
                                enabled: available,
                              ),
                              const SizedBox(width: AppGap.xs),
                              // right indicator: show check only when selected
                              Builder(builder: (_) {
                                final sp2 = context.watch<SettingsProvider>();
                                final sel = sp2.usingSystemTts;
                                return sel
                                    ? Icon(Lucide.Check, size: 16, color: c)
                                    : const SizedBox(width: 16);
                              }),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                if (services.isNotEmpty) const SettingsDivider(),
                if (services.isNotEmpty) ...[
                  for (int i = 0; i < services.length; i++) ...[
                    _NetworkTtsRowMobile(service: services[i], index: i),
                    if (i != services.length - 1) const SettingsDivider(),
                  ]
                ],
              ]),
            ],
          );
        },
      ),
    );
  }
}

// --- iOS-style widgets and helpers ---

/// 行内小图标按钮（试听 / 配置 / 删除）。
///
/// **保留私有**：它的视觉语义与 `IosIconButton` 不同 ——
/// 启用态 0.9 透明度、按压 0.6、禁用 0.3，且按压无底色变化；
/// `IosIconButton` 是「向白/黑混合 + 按压底色」，硬套会改观感。
class _SmallTactileIcon extends StatefulWidget {
  const _SmallTactileIcon(
      {required this.icon, required this.onTap, this.enabled = true, this.baseColor});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final Color? baseColor;
  @override
  State<_SmallTactileIcon> createState() => _SmallTactileIconState();
}

class _SmallTactileIconState extends State<_SmallTactileIcon> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = widget.baseColor ?? cs.onSurface;
    final c = widget.enabled
        ? base.withOpacity(_pressed ? 0.6 : 0.9)
        : base.withOpacity(0.3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled
          ? () {
              Haptics.soft();
              widget.onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(widget.icon, size: 18, color: c),
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.letter, required this.overlay});
  final String letter;
  final Color overlay;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: baseBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(letter,
              style: TextStyle(
                  color: cs.primary, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        if (overlay != Colors.transparent)
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: overlay, shape: BoxShape.circle)),
      ],
    );
  }
}

class _AvatarBrandBadge extends StatelessWidget {
  const _AvatarBrandBadge({required this.name, required this.overlay});
  final String name;
  final Color overlay;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);
    final asset = BrandAssets.assetForName(name) ??
        BrandAssets.assetForName(name.split(' ').first);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: baseBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: asset == null
              ? Text((name.isEmpty ? '?' : name[0]).toUpperCase(),
                  style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14))
              : (asset.endsWith('.svg')
                  ? SvgPicture.asset(asset, width: 20, height: 20)
                  : Image.asset(asset, width: 20, height: 20, fit: BoxFit.contain)),
        ),
        if (overlay != Colors.transparent)
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: overlay, shape: BoxShape.circle)),
      ],
    );
  }
}

class _NetworkTtsRowMobile extends StatefulWidget {
  const _NetworkTtsRowMobile({required this.service, required this.index});
  final TtsServiceOptions service;
  final int index;
  @override
  State<_NetworkTtsRowMobile> createState() => _NetworkTtsRowMobileState();
}

class _NetworkTtsRowMobileState extends State<_NetworkTtsRowMobile> {
  bool _testing = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = widget.service.name.trim().isEmpty
        ? networkTtsKindDisplayName(widget.service.kind)
        : widget.service.name.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IosTactileRow(
          pressedScale: 0.98,
          haptics: false,
          onTap: () async =>
              context.read<SettingsProvider>().setTtsServiceSelected(widget.index),
          builder: (_, pressed) {
            final base = cs.onSurface.withOpacity(0.9);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final overlay = pressed
                ? (isDark
                    ? Colors.black.withOpacity(0.06)
                    : Colors.white.withOpacity(0.05))
                : Colors.transparent;
            return IosPressColor(
              pressed: pressed,
              base: base,
              builder: (c) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
                  child: Row(
                    children: [
                      _AvatarBrandBadge(name: displayName, overlay: overlay),
                      const SizedBox(width: AppGap.sm),
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15, color: c, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: AppGap.xs),
                      _SmallTactileIcon(
                        icon: Lucide.Settings2,
                        baseColor: c,
                        onTap: () async {
                          final updated =
                              await _showEditNetworkTtsSheet(context, widget.service);
                          if (updated != null) {
                            final list = List<TtsServiceOptions>.from(
                                context.read<SettingsProvider>().ttsServices);
                            list[widget.index] = updated;
                            await context
                                .read<SettingsProvider>()
                                .setTtsServices(list);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _SmallTactileIcon(
                        icon: _testing ? Lucide.Loader : Lucide.Volume2,
                        baseColor: c,
                        onTap: () async {
                          setState(() {
                            _testing = true;
                            _error = null;
                          });
                          final demo = context.l10n
                              .ttsServicesPageTestSpeechText;
                          final err = await context
                              .read<TtsProvider>()
                              .testNetworkService(widget.service, demo);
                          if (!mounted) return;
                          setState(() {
                            _testing = false;
                            _error = err;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _SmallTactileIcon(
                        icon: Lucide.Trash2,
                        baseColor: c,
                        onTap: () async {
                          final sp = context.read<SettingsProvider>();
                          final list = List<TtsServiceOptions>.from(sp.ttsServices);
                          list.removeAt(widget.index);
                          await sp.setTtsServices(list);
                          var idx = sp.ttsServiceSelected;
                          if (idx >= list.length) {
                            idx = list.isEmpty ? -1 : list.length - 1;
                          }
                          await sp.setTtsServiceSelected(idx);
                        },
                      ),
                      const SizedBox(width: AppGap.xs),
                      Builder(builder: (_) {
                        final sp2 = context.watch<SettingsProvider>();
                        final sel = (sp2.ttsServiceSelected == widget.index);
                        return sel
                            ? Icon(Lucide.Check, size: 16, color: c)
                            : const SizedBox(width: 16);
                      }),
                    ],
                  ),
                );
              },
            );
          },
        ),
        if (_error != null && _error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ErrorInlineMobile(message: _error!),
        ],
      ],
    );
  }
}

class _ErrorInlineMobile extends StatelessWidget {
  const _ErrorInlineMobile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final oneLine = message.replaceAll('\n', ' ');
    return Container(
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.08),
        // 10 无精确 token（sm=8 / md=12），保留字面量
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withOpacity(0.3), width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppGap.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(oneLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.error)),
          ),
          const SizedBox(width: AppGap.xs),
          TextButton(
            onPressed: () => _showMobileErrorDetails(context, message),
            child: Text(l10n.ttsServicesViewDetailsButton),
          ),
        ],
      ),
    );
  }
}

/// 错误详情弹层：把手 + 左对齐标题 + 可选中全文 + 右下关闭。
/// 结构与 `AppSheet`（title / children / footer）一一对应，故整体收敛。
void _showMobileErrorDetails(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  showAppSheet<void>(
    context: context,
    builder: AppSheet(
      title: l10n.ttsServicesDialogErrorTitle,
      contentPadding: const EdgeInsets.fromLTRB(AppGap.sm, 4, AppGap.sm, AppGap.md),
      // ignore: sort_child_properties_last —— AppSheet 语义顺序是 title → children → footer，与 lint 的「children 放最后」冲突
      children: [
        SelectableText(message,
            style: TextStyle(color: cs.onSurface.withOpacity(0.9), fontSize: 13)),
      ],
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.ttsServicesCloseButton),
        ),
      ),
    ),
  );
}

// Removed selected tag; background highlight indicates selection

Future<TtsServiceOptions?> _showAddNetworkTtsSheet(BuildContext context) =>
    _showNetworkTtsSheet(context, null);

Future<TtsServiceOptions?> _showEditNetworkTtsSheet(
        BuildContext context, TtsServiceOptions initial) =>
    _showNetworkTtsSheet(context, initial);

Future<TtsServiceOptions?> _showNetworkTtsSheet(
    BuildContext context, TtsServiceOptions? initial) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  NetworkTtsKind kind = initial?.kind ?? NetworkTtsKind.openai;
  final nameCtl = TextEditingController(text: initial?.name ?? '');
  final apiKeyCtl = TextEditingController(text: (initial is OpenAiTtsOptions)
      ? initial.apiKey
      : (initial is GeminiTtsOptions)
          ? initial.apiKey
          : (initial is MiniMaxTtsOptions)
              ? initial.apiKey
              : (initial is ElevenLabsTtsOptions)
                  ? initial.apiKey
                  : '');
  final baseCtl = TextEditingController(text: (initial is OpenAiTtsOptions)
      ? initial.baseUrl
      : (initial is GeminiTtsOptions)
          ? initial.baseUrl
          : (initial is MiniMaxTtsOptions)
              ? initial.baseUrl
              : (initial is ElevenLabsTtsOptions)
                  ? initial.baseUrl
                  : '');
  final modelCtl = TextEditingController(text: (initial is OpenAiTtsOptions)
      ? initial.model
      : (initial is GeminiTtsOptions)
          ? initial.model
          : (initial is MiniMaxTtsOptions)
              ? initial.model
              : (initial is ElevenLabsTtsOptions)
                  ? initial.modelId
                  : '');
  final voiceCtl = TextEditingController(text: (initial is OpenAiTtsOptions)
      ? initial.voice
      : (initial is GeminiTtsOptions)
          ? initial.voiceName
          : (initial is MiniMaxTtsOptions)
              ? initial.voiceId
              : (initial is ElevenLabsTtsOptions)
                  ? initial.voiceId
                  : '');
  final emotionCtl =
      TextEditingController(text: (initial is MiniMaxTtsOptions) ? initial.emotion : 'calm');
  final speedCtl = TextEditingController(
      text: (initial is MiniMaxTtsOptions) ? initial.speed.toString() : '1.0');

  TtsServiceOptions? result;
  await showAppSheet<void>(
    context: context,
    // 自建内容：头部是「左关闭 | 居中标题 | 右确认」三段式，
    // `AppSheet.title` 只有左对齐一种，套不进去。把手需自己画。
    builder: Builder(
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppRadius.circular)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppGap.xxs, 6, AppGap.xxs, 6),
            child: Row(
              children: [
                IosIconButton(
                  haptics: true,
                  icon: Lucide.X,
                  color: cs.onSurface,
                  size: 20,
                  onTap: () => Navigator.of(sheetCtx).maybePop(),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                        initial == null
                            ? l10n.ttsServicesDialogAddTitle
                            : l10n.ttsServicesDialogEditTitle,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                IosIconButton(
                  haptics: true,
                  icon: Lucide.Check,
                  color: cs.onSurface,
                  size: 20,
                  onTap: () {
                    final name = (nameCtl.text.trim().isEmpty)
                        ? networkTtsKindDisplayName(kind)
                        : nameCtl.text.trim();
                    final apiKey = apiKeyCtl.text.trim();
                    final base = baseCtl.text.trim().isEmpty
                        ? _defaultBaseUrl(kind)
                        : baseCtl.text.trim();
                    final model = modelCtl.text.trim().isEmpty
                        ? _defaultModel(kind)
                        : modelCtl.text.trim();
                    final voice = voiceCtl.text.trim().isEmpty
                        ? _defaultVoice(kind)
                        : voiceCtl.text.trim();
                    if (apiKey.isEmpty) {
                      Navigator.of(sheetCtx).maybePop();
                      return;
                    }
                    if (kind == NetworkTtsKind.openai) {
                      result = OpenAiTtsOptions(
                          enabled: true,
                          name: name,
                          apiKey: apiKey,
                          baseUrl: base,
                          model: model,
                          voice: voice);
                    } else if (kind == NetworkTtsKind.gemini) {
                      result = GeminiTtsOptions(
                          enabled: true,
                          name: name,
                          apiKey: apiKey,
                          baseUrl: base,
                          model: model,
                          voiceName: voice);
                    } else if (kind == NetworkTtsKind.minimax) {
                      final spd = double.tryParse(speedCtl.text.trim()) ?? 1.0;
                      result = MiniMaxTtsOptions(
                          enabled: true,
                          name: name,
                          apiKey: apiKey,
                          baseUrl: base,
                          model: model,
                          voiceId: voice,
                          emotion: emotionCtl.text.trim().isEmpty
                              ? 'calm'
                              : emotionCtl.text.trim(),
                          speed: spd);
                    } else {
                      // ElevenLabs
                      result = ElevenLabsTtsOptions(
                          enabled: true,
                          name: name,
                          apiKey: apiKey,
                          baseUrl: base,
                          modelId:
                              model.isEmpty ? _defaultModel(kind) : model,
                          voiceId: voice);
                    }
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // showAppSheet 已统一处理 SafeArea 与键盘避让，这里只留横向留白
          Padding(
            padding:
                const EdgeInsets.only(left: AppGap.sm, right: AppGap.sm, bottom: AppGap.sm),
            child: StatefulBuilder(
              builder: (ctx2, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sheetSelectRow(
                      ctx2,
                      label: l10n.ttsServicesDialogProviderType,
                      value: networkTtsKindDisplayName(kind),
                      options: [
                        networkTtsKindDisplayName(NetworkTtsKind.openai),
                        networkTtsKindDisplayName(NetworkTtsKind.gemini),
                        networkTtsKindDisplayName(NetworkTtsKind.minimax),
                        networkTtsKindDisplayName(NetworkTtsKind.elevenlabs),
                      ],
                      // 原实现是 `(ctx as Element).markNeedsBuild()`，
                      // 改用 StatefulBuilder 自身的 setState，语义一致且更直白
                      onSelected: (picked) async {
                        setSheetState(() {
                          if (picked ==
                              networkTtsKindDisplayName(NetworkTtsKind.openai)) {
                            kind = NetworkTtsKind.openai;
                          }
                          if (picked ==
                              networkTtsKindDisplayName(NetworkTtsKind.gemini)) {
                            kind = NetworkTtsKind.gemini;
                          }
                          if (picked ==
                              networkTtsKindDisplayName(NetworkTtsKind.minimax)) {
                            kind = NetworkTtsKind.minimax;
                          }
                          if (picked ==
                              networkTtsKindDisplayName(NetworkTtsKind.elevenlabs)) {
                            kind = NetworkTtsKind.elevenlabs;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    _inputRowMobile(context,
                        label: l10n.ttsServicesFieldNameLabel,
                        controller: nameCtl,
                        hint: networkTtsKindDisplayName(kind)),
                    const SizedBox(height: 6),
                    _inputRowMobile(context,
                        label: l10n.ttsServicesFieldApiKeyLabel,
                        controller: apiKeyCtl,
                        obscure: true),
                    const SizedBox(height: 6),
                    _inputRowMobile(context,
                        label: l10n.ttsServicesFieldBaseUrlLabel,
                        controller: baseCtl,
                        hint: _defaultBaseUrl(kind)),
                    const SizedBox(height: 6),
                    _inputRowMobile(context,
                        label: l10n.ttsServicesFieldModelLabel,
                        controller: modelCtl,
                        hint: _defaultModel(kind)),
                    const SizedBox(height: 6),
                    _inputRowMobile(context,
                        label: _voiceLabelFor(kind, l10n),
                        controller: voiceCtl,
                        hint: _defaultVoice(kind)),
                    if (kind == NetworkTtsKind.minimax) ...[
                      const SizedBox(height: 6),
                      _inputRowMobile(context,
                          label: l10n.ttsServicesFieldEmotionLabel,
                          controller: emotionCtl,
                          hint: 'calm'),
                      const SizedBox(height: 6),
                      _inputRowMobile(context,
                          label: l10n.ttsServicesFieldSpeedLabel,
                          controller: speedCtl,
                          hint: '1.0'),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<void> _showSystemTtsConfig(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  final tts = context.read<TtsProvider>();
  double rate = tts.speechRate;
  double pitch = tts.pitch;
  await showAppSheet<void>(
    context: context,
    builder: AppSheet(
      title: l10n.ttsServicesPageSystemTtsSettingsTitle,
      contentPadding: const EdgeInsets.fromLTRB(AppGap.sm, 4, AppGap.sm, AppGap.md),
      // ignore: sort_child_properties_last —— AppSheet 语义顺序是 title → children → footer，与 lint 的「children 放最后」冲突
      children: [
        StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Engine selector
                FutureBuilder<List<String>>(
                  future: tts.listEngines(),
                  builder: (context, snap) {
                    final engines = snap.data ?? const <String>[];
                    final cur =
                        tts.engineId ?? (engines.isNotEmpty ? engines.first : '');
                    return _sheetSelectRow(
                      ctx,
                      label: l10n.ttsServicesPageEngineLabel,
                      value: cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur,
                      options: engines,
                      onSelected: (picked) async {
                        await tts.setEngineId(picked);
                        setSheetState(() {});
                      },
                    );
                  },
                ),
                const SizedBox(height: AppGap.xxs),
                // Language selector
                FutureBuilder<List<String>>(
                  future: tts.listLanguages(),
                  builder: (context, snap) {
                    final langs = snap.data ?? const <String>[];
                    final cur = tts.languageTag ??
                        (langs.contains('zh-CN')
                            ? 'zh-CN'
                            : (langs.contains('en-US')
                                ? 'en-US'
                                : (langs.isNotEmpty ? langs.first : '')));
                    return _sheetSelectRow(
                      ctx,
                      label: l10n.ttsServicesPageLanguageLabel,
                      value: cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur,
                      options: langs,
                      onSelected: (picked) async {
                        await tts.setLanguageTag(picked);
                        setSheetState(() {});
                      },
                    );
                  },
                ),
                const SizedBox(height: AppGap.xs),
                Text(l10n.ttsServicesPageSpeechRateLabel,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                Slider(
                  value: rate,
                  min: 0.1,
                  max: 1.0,
                  onChanged: (v) => setSheetState(() => rate = v),
                  onChangeEnd: (v) async {
                    await tts.setSpeechRate(v);
                  },
                ),
                const SizedBox(height: AppGap.xxs),
                Text(l10n.ttsServicesPagePitchLabel,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                Slider(
                  value: pitch,
                  min: 0.5,
                  max: 2.0,
                  onChanged: (v) => setSheetState(() => pitch = v),
                  onChangeEnd: (v) async {
                    await tts.setPitch(v);
                  },
                ),
              ],
            );
          },
        ),
      ],
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () async {
            final demo = l10n.ttsServicesPageSettingsSavedMessage;
            Navigator.of(context).maybePop();
            showAppSnackBar(context, message: demo, type: NotificationType.success);
          },
          icon: const Icon(Lucide.Check, size: 16),
          label: Text(l10n.ttsServicesPageDoneButton),
        ),
      ),
    ),
  );
}

/// 弹层里的选择行：标签 + 当前值 + 右箭头，点开二级选项弹层。
/// 这是「无前置图标的导航行」，`SettingsNavRow` 要求必须有图标，故保留私有。
Widget _sheetSelectRow(
  BuildContext context, {
  required String label,
  required String value,
  required List<String> options,
  required Future<void> Function(String picked) onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  return IosTactileRow(
    onTap: options.isEmpty
        ? null
        : () async {
            final picked = await showAppSheet<String>(
              context: context,
              builder: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (c, i) => _sheetDivider(context),
                  itemBuilder: (c, i) => _sheetOption(
                    context,
                    label: options[i],
                    onTap: () => Navigator.of(context).pop(options[i]),
                  ),
                ),
              ),
            );
            if (picked != null && picked.isNotEmpty) {
              await onSelected(picked);
            }
          },
    builder: (_, pressed) {
      final baseColor = cs.onSurface.withOpacity(0.9);
      return IosPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
            child: Row(
              children: [
                Expanded(
                    child: Text(label, style: TextStyle(fontSize: 15, color: c))),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                ),
                Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

// Bottom sheet iOS-style option
Widget _sheetOption(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return IosTactileRow(
    onTap: onTap,
    haptics: true,
    builder: (_, pressed) {
      final bgTarget = pressed
          ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
          : Colors.transparent;
      return IosPressColor(
        pressed: pressed,
        base: cs.onSurface,
        builder: (c) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          color: bgTarget,
          // 14 无精确 token（sm=12 / md=16），保留字面量
          padding: const EdgeInsets.symmetric(horizontal: AppGap.md, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c)))
          ]),
        ),
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
      height: 1,
      thickness: 0.6,
      indent: AppGap.md,
      endIndent: AppGap.md,
      color: cs.outlineVariant.withOpacity(0.18));
}

Widget _inputRowMobile(BuildContext context,
    {required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            // 10 无精确 token，保留字面量
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ),
  );
}

String _defaultBaseUrl(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'https://api.openai.com/v1';
    case NetworkTtsKind.gemini:
      return 'https://generativelanguage.googleapis.com/v1beta';
    case NetworkTtsKind.minimax:
      return 'https://api.minimaxi.com/v1';
    case NetworkTtsKind.elevenlabs:
      return 'https://api.elevenlabs.io';
  }
}

String _defaultModel(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'gpt-4o-mini-tts';
    case NetworkTtsKind.gemini:
      return 'gemini-2.5-flash-preview-tts';
    case NetworkTtsKind.minimax:
      return 'speech-2.5-hd-preview';
    case NetworkTtsKind.elevenlabs:
      return 'eleven_multilingual_v2';
  }
}

String _defaultVoice(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'alloy';
    case NetworkTtsKind.gemini:
      return 'Kore';
    case NetworkTtsKind.minimax:
      return 'female-shaonv';
    case NetworkTtsKind.elevenlabs:
      return '';
  }
}

String _voiceLabelFor(NetworkTtsKind k, AppLocalizations l10n) {
  switch (k) {
    case NetworkTtsKind.openai:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.gemini:
      return l10n.ttsServicesFieldVoiceLabel; // same label
    case NetworkTtsKind.minimax:
      return l10n.ttsServicesFieldVoiceIdLabel;
    case NetworkTtsKind.elevenlabs:
      return l10n.ttsServicesFieldVoiceIdLabel;
  }
}
