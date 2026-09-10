import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart' as lucide;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../settings/widgets/language_select_sheet.dart' show LanguageOption, supportedLanguages, showLanguageSelector;
import '../../model/widgets/model_select_sheet.dart' show showModelSelector;

/// 翻译页：固定高度输入区 + 可伸缩输出区 + 底部「目标语言 / 翻译」操作条。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + `SafeArea(Column[...])` → `AppPage.selfScrolling(body:, bottom:)`
///   - 底部操作条（语言选择 + 翻译/停止）→ **`bottom:` 槽位**
///   - 引擎已对 body 套 SafeArea，故删除页面自带的 `SafeArea`
///   - `bottomNavigationBar` 在 SafeArea 之外，所以底栏单独补 `SafeArea(top: false)`
/// - `scrollable: false` + `bodyPadding: zero`：两个 TextField 都是 `expands: true` /
///   `maxLines: null`，必须有界高度；内边距由各区自己声明
/// - **私有 `_TactileIconButton` → 共享 `IosIconButton`**，随之移除 `haptics` import
/// - 魔法数字 → AppGap / AppRadius
class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final TextEditingController _src = TextEditingController();
  final TextEditingController _dst = TextEditingController();
  LanguageOption? _lang;
  String? _providerKey;
  String? _modelId;
  StreamSubscription? _sub;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaults());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _src.dispose();
    _dst.dispose();
    super.dispose();
  }

  void _initDefaults() {
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    // 默认语言
    final lc = Localizations.localeOf(context).languageCode.toLowerCase();
    setState(() {
      if (lc.startsWith('zh')) {
        _lang = supportedLanguages.firstWhere((e) => e.code == 'zh-CN', orElse: () => supportedLanguages.first);
      } else {
        _lang = supportedLanguages.firstWhere((e) => e.code == 'en', orElse: () => supportedLanguages.first);
      }
      _providerKey = settings.translateModelProvider ?? assistant?.chatModelProvider ?? settings.currentModelProvider;
      _modelId = settings.translateModelId ?? assistant?.chatModelId ?? settings.currentModelId;
    });
  }

  Future<void> _pickModel() async {
    if (_loading) return;
    final sel = await showModelSelector(context);
    if (!mounted) return;
    if (sel != null) {
      setState(() {
        _providerKey = sel.providerKey;
        _modelId = sel.modelId;
      });
      // 记住翻译模型选择，下次进入自动回填
      await context.read<SettingsProvider>().setTranslateModel(sel.providerKey, sel.modelId);
    }
  }

  Future<void> _pickLanguage() async {
    if (_loading) return;
    final lang = await showLanguageSelector(context);
    if (!mounted || lang == null) return;
    if (lang.code == '__clear__') {
      setState(() => _dst.clear());
      return;
    }
    setState(() => _lang = lang);
  }

  Future<void> _translate() async {
    final l10n = context.l10n;
    final txt = _src.text.trim();
    if (txt.isEmpty) return;
    final pk = _providerKey;
    final mid = _modelId;
    if (pk == null || mid == null) {
      showAppSnackBar(context, message: l10n.homePagePleaseSetupTranslateModel, type: NotificationType.warning);
      return;
    }
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(pk);
    final p = settings.translatePrompt
        .replaceAll('{source_text}', txt)
        .replaceAll('{target_lang}', _displayNameFor(l10n, (_lang ?? supportedLanguages.first).code));

    setState(() {
      _loading = true;
      _dst.text = '';
    });

    try {
      final stream = ChatApiService.sendMessageStream(
        config: cfg,
        modelId: mid,
        messages: [
          {'role': 'user', 'content': p},
        ],
      );
      _sub = stream.listen(
        (chunk) {
          final s = chunk.content;
          if (_dst.text.isEmpty) {
            // 去掉首个分块的前导空白，避免译文顶部出现空行
            final cleaned = s.replaceFirst(RegExp(r'^\s+'), '');
            _dst.text = cleaned;
          } else {
            _dst.text += s;
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          showAppSnackBar(context, message: l10n.homePageTranslateFailed(e.toString()), type: NotificationType.error);
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _loading = false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() => _loading = false);
      showAppSnackBar(context, message: l10n.homePageTranslateFailed(e.toString()), type: NotificationType.error);
    }
  }

  Future<void> _stop() async {
    try { await _sub?.cancel(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _displayNameFor(AppLocalizations l10n, String code) {
    switch (code) {
      case 'zh-CN': return l10n.languageDisplaySimplifiedChinese;
      case 'en': return l10n.languageDisplayEnglish;
      case 'zh-TW': return l10n.languageDisplayTraditionalChinese;
      case 'ja': return l10n.languageDisplayJapanese;
      case 'ko': return l10n.languageDisplayKorean;
      case 'fr': return l10n.languageDisplayFrench;
      case 'de': return l10n.languageDisplayGerman;
      case 'it': return l10n.languageDisplayItalian;
      case 'es': return l10n.languageDisplaySpanish;
      default: return code;
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    setState(() { _src.text = text; });
  }

  Future<void> _copyResult() async {
    await Clipboard.setData(ClipboardData(text: _dst.text));
    if (!mounted) return;
    showAppSnackBar(context, message: context.l10n.chatMessageWidgetCopiedToClipboard, type: NotificationType.success);
  }

  Future<void> _clearAll() async {
    await _stop();
    setState(() { _src.clear(); _dst.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = (_modelId != null) ? BrandAssets.assetForName(_modelId!) : null;

    return AppPage.selfScrolling(
      title: l10n.desktopNavTranslateTooltip,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: lucide.Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        // 粘贴
        Tooltip(
          message: l10n.translatePagePasteButton,
          child: Padding(
            padding: const EdgeInsets.only(right: AppGap.xxs),
            child: IosIconButton(
              haptics: true,
              icon: lucide.Lucide.Clipboard,
              size: 20,
              padding: const EdgeInsets.all(AppGap.xs),
              onTap: _pasteFromClipboard,
            ),
          ),
        ),
        // 复制结果
        Tooltip(
          message: l10n.translatePageCopyResult,
          child: Padding(
            padding: const EdgeInsets.only(right: AppGap.xxs),
            child: IosIconButton(
              haptics: true,
              icon: lucide.Lucide.Copy,
              size: 20,
              padding: const EdgeInsets.all(AppGap.xs),
              onTap: _copyResult,
            ),
          ),
        ),
        // 清空
        Tooltip(
          message: l10n.translatePageClearAll,
          child: Padding(
            padding: const EdgeInsets.only(right: AppGap.xxs),
            child: IosIconButton(
              haptics: true,
              icon: lucide.Lucide.Eraser,
              size: 20,
              padding: const EdgeInsets.all(AppGap.xs),
              onTap: _clearAll,
            ),
          ),
        ),
        // 模型品牌图标（保留原色）
        Padding(
          padding: const EdgeInsets.only(right: AppGap.xs),
          child: IosIconButton(
            haptics: true,
            padding: const EdgeInsets.all(AppGap.xs),
            builder: (color) {
              if (asset != null && asset.toLowerCase().endsWith('.svg')) {
                return SvgPicture.asset(asset, width: 22, height: 22);
              }
              if (asset != null) {
                return Image.asset(asset, width: 22, height: 22);
              }
              return Icon(lucide.Lucide.Bot, size: 22, color: color);
            },
            onTap: _pickModel,
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 输入
          Padding(
            padding: const EdgeInsets.fromLTRB(AppGap.md, 10, AppGap.md, 6),
            child: SizedBox(
              height: 200,
              child: _Card(
                child: TextField(
                  controller: _src,
                  keyboardType: TextInputType.multiline,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: InputDecoration(
                    hintText: l10n.translatePageInputHint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(
                        AppGap.sm, AppGap.xs, AppGap.sm, AppGap.sm),
                  ),
                  contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
          // 输出
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.md, 10, AppGap.md, 6),
              child: _Card(
                child: TextField(
                  controller: _dst,
                  readOnly: true,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  expands: true,
                  decoration: InputDecoration(
                    hintText: l10n.translatePageOutputHint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(
                        AppGap.sm, AppGap.xs, AppGap.sm, AppGap.sm),
                  ),
                  enableInteractiveSelection: false,
                  contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
        ],
      ),
      // 底部：目标语言 + 翻译/停止
      bottom: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.md, 0, AppGap.md, AppGap.sm),
              child: Row(
                children: [
                  Expanded(
                    child: IosCardPress(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      baseColor: Theme.of(context).cardColor,
                      onTap: _pickLanguage,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppGap.xs),
                      child: Row(
                        children: [
                          Text((_lang ?? supportedLanguages.first).flag, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _displayNameFor(l10n, (_lang ?? supportedLanguages.first).code),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(lucide.Lucide.ChevronDown, size: 18, color: cs.onSurface.withOpacity(0.7)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppGap.sm),
                  IosCardPress(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    baseColor: cs.primary,
                    pressedBlendStrength: isDark ? 0.08 : 0.06,
                    onTap: _loading ? _stop : _translate,
                    padding: const EdgeInsets.symmetric(horizontal: AppGap.md, vertical: AppGap.xs),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                      child: _loading
                          ? Row(
                              key: const ValueKey('stop'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset('assets/icons/stop.svg', width: 18, height: 18, colorFilter: ColorFilter.mode(isDark ? Colors.black : Colors.white, BlendMode.srcIn)),
                                const SizedBox(width: AppGap.xs),
                                Text(l10n.chatMessageWidgetStopTooltip, style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.w700)),
                              ],
                            )
                          : Row(
                              key: const ValueKey('go'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(lucide.Lucide.Languages, size: 18, color: isDark ? Colors.black : Colors.white),
                                const SizedBox(width: AppGap.xs),
                                Text(l10n.chatMessageWidgetTranslateTooltip, style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
