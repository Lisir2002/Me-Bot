import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/api_keys.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/card_surface.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../model/widgets/model_select_sheet.dart';

// ──────────────────────────────────────────────────────────────
// 迁移到 AppPage 骨架（批次 3，1025 行 → ~700 行）
//
// 骨架层：
//   Scaffold + AppBar + ListView      → AppPage(title / actions / bodyPadding / body)
//   AppBar leading 的私有返回按钮      → AppPage 默认 showBack（IosIconButton，带 44 点击区）
//   ListView(padding: 16,12,16,16)    → bodyPadding = fromLTRB(md, sm, md, md)
//   顶层 Column                       → crossAxisAlignment: stretch（清单 3d：
//                                       scrollable:true 时子项宽度是紧约束，
//                                       Column 默认 center 会让卡片缩成内容宽）
//
// 组件层：
//   _TactileIconButton（3 处 AppBar + 每 key 的编辑/删除）
//                                     → IosIconButton(haptics: true, minSize: 44)
//   _TactileRow（策略行）              → IosTactileRow + IosPressColor（不缩放）
//   _TactileScale                     → 删除（只被 _iosRow 的 onTap 分支用，而该分支无调用点）
//   _iosSectionCard                   → _sectionCard（改用 AppCardSurface，与
//                                       default_model / network_proxy 一致）
//   _iosRow                           → _statRow（去掉死掉的 onTap 分支）
//   _divider / _chooseDetectModel     → 删除（无引用）
//   _showStrategySheet                → showAppSheet + AppSheet（带把手 + 选中打勾）
//   _showAddKeysSheet / _showEditKeySheet
//                                     → showAppSheet + 自建（居中标题 + 左侧关闭，
//                                       AppSheet.title 只有左对齐，套不进去）
//                                       两者共用的头部/输入框抽成 _formSheetHeader / _formField
//
// 顺带清理：package:provider/provider.dart 与 settings_provider.dart 各 import 两遍、
// flutter/cupertino.dart 无引用、core/services/haptics.dart 改由 IosIconButton 内部触发。
//
// 仍留在本地的私有件：
//   _sectionCard —— 与 settings / storage 家族的 SectionCard 是同一形状的第三份；
//                   provider 页不便反向依赖 features/settings，故先本地保留
//                   （全仓 12 份 `_iosSectionCard` 的统一收敛见迁移计划「待办 F」）
// ──────────────────────────────────────────────────────────────

class MultiKeyManagerPage extends StatefulWidget {
  const MultiKeyManagerPage({super.key, required this.providerKey, required this.providerDisplayName});
  final String providerKey;
  final String providerDisplayName;

  @override
  State<MultiKeyManagerPage> createState() => _MultiKeyManagerPageState();
}

class _MultiKeyManagerPageState extends State<MultiKeyManagerPage> {
  String? _detectModelId;
  bool _detecting = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final apiKeys = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final total = apiKeys.length;
    final normal = apiKeys.where((k) => k.status == ApiKeyStatus.active).length;
    final errors = apiKeys.where((k) => k.status == ApiKeyStatus.error).length;

    return AppPage(
      title: l10n.multiKeyPageTitle,
      actions: [
        Tooltip(
          message: l10n.multiKeyPageDeleteErrorsTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Trash2,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.multiKeyPageDeleteErrorsTooltip,
            onTap: _onDeleteAllErrorKeys,
          ),
        ),
        if (_detecting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          )
        else
          Tooltip(
            message: l10n.multiKeyPageDetect,
            child: IosIconButton(
              haptics: true,
              icon: Lucide.HeartPulse,
              color: cs.onSurface,
              size: 22,
              minSize: 44,
              semanticLabel: l10n.multiKeyPageDetect,
              onTap: _onDetect,
              onLongPress: _onPickDetectModel,
            ),
          ),
        Tooltip(
          message: l10n.multiKeyPageAdd,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.multiKeyPageAdd,
            onTap: _onAddKeys,
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionCard(children: [
            _statRow(context, label: l10n.multiKeyPageTotal, value: '$total'),
            _statRow(context, label: l10n.multiKeyPageNormal, value: '$normal'),
            _statRow(context, label: l10n.multiKeyPageError, value: '$errors'),
            _strategyRow(context, cfg),
          ]),
          const SizedBox(height: AppGap.sm),
          _keysList(context, apiKeys),
        ],
      ),
    );
  }

  String _strategyLabel(BuildContext context, LoadBalanceStrategy s) {
    final l10n = context.l10n;
    switch (s) {
      case LoadBalanceStrategy.priority:
        return l10n.multiKeyPageStrategyPriority;
      case LoadBalanceStrategy.leastUsed:
        return l10n.multiKeyPageStrategyLeastUsed;
      case LoadBalanceStrategy.random:
        return l10n.multiKeyPageStrategyRandom;
      case LoadBalanceStrategy.roundRobin:
      default: // ignore: unreachable_switch_default
        return l10n.multiKeyPageStrategyRoundRobin;
    }
  }

  Widget _strategyRow(BuildContext context, ProviderConfig cfg) {
    final cs = Theme.of(context).colorScheme;
    final strategy = cfg.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;
    return IosTactileRow(
      onTap: _showStrategySheet,
      builder: (ctx, pressed) {
        return IosPressColor(
          pressed: pressed,
          base: cs.onSurface,
          builder: (c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ctx.l10n.multiKeyPageStrategyTitle,
                    style: TextStyle(fontSize: 15, color: c),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_strategyLabel(ctx, strategy), style: TextStyle(fontSize: 15, color: c)),
                    const SizedBox(width: 6),
                    Icon(Lucide.ChevronRight, size: 16, color: c),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _keysList(BuildContext context, List<ApiKeyConfig> keys) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    if (keys.isEmpty) {
      return _sectionCard(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(child: Text(l10n.multiKeyPageNoKeys)),
        )
      ]);
    }

    String mask(String key) {
      if (key.length <= 8) return key;
      return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
    }

    Color statusColor(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return Colors.green;
        case ApiKeyStatus.disabled:
          return cs.onSurface.withOpacity(0.6);
        case ApiKeyStatus.error:
          return cs.error;
        case ApiKeyStatus.rateLimited:
          return cs.tertiary;
      }
    }

    String statusText(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return l10n.multiKeyPageStatusActive;
        case ApiKeyStatus.disabled:
          return l10n.multiKeyPageStatusDisabled;
        case ApiKeyStatus.error:
          return l10n.multiKeyPageStatusError;
        case ApiKeyStatus.rateLimited:
          return l10n.multiKeyPageStatusRateLimited;
      }
    }

    return _sectionCard(
      children: [
        for (int i = 0; i < keys.length; i++)
          _keyRow(context, keys[i], statusColor, statusText, mask),
      ],
    );
  }

  Widget _keyRow(
    BuildContext context,
    ApiKeyConfig k,
    Color Function(ApiKeyStatus) statusColor,
    String Function(ApiKeyStatus) statusText,
    String Function(String) mask,
  ) {
    final cs = Theme.of(context).colorScheme;
    final name = k.name?.isNotEmpty == true ? k.name! : mask(k.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.sm),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: AppGap.xxxs),
                  decoration: BoxDecoration(
                    color: statusColor(k.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.circular),
                  ),
                  child: Text(
                    statusText(k.status),
                    style: TextStyle(color: statusColor(k.status), fontSize: 11),
                  ),
                ),
                const SizedBox(width: AppGap.xs),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppGap.xs),
          IosSwitch(
            value: k.isEnabled,
            onChanged: (v) async {
              await _updateKey(k.copyWith(isEnabled: v));
            },
            width: 46,
            height: 28,
          ),
          const SizedBox(width: 6),
          IosIconButton(
            haptics: true,
            icon: Lucide.Pencil,
            color: cs.primary,
            size: 22,
            semanticLabel: context.l10n.multiKeyPageEdit,
            onTap: () async {
              await _editKey(k);
            },
          ),
          const SizedBox(width: AppGap.xxs),
          IosIconButton(
            haptics: true,
            icon: Lucide.Trash2,
            color: cs.error,
            size: 22,
            semanticLabel: context.l10n.multiKeyPageDelete,
            onTap: () async {
              await _deleteKey(k);
            },
          ),
        ],
      ),
    );
  }

  /// iOS 风格分组卡片。
  ///
  /// 底色/描边统一走 `AppCardSurface`，与 `default_model` / `network_proxy` 对齐
  /// （原实现用 `Color.lerp(surface, white, 0.06 / 0.92)` + 0.6 描边，观感几乎一致）。
  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppCardSurface.background(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: AppCardSurface.border(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// 统计行：左侧标签 + 右侧数值（不可点）。
  Widget _statRow(BuildContext context, {required String label, required String value}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Padding(
            padding: const EdgeInsets.only(right: AppGap.sm),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateKey(ApiKeyConfig updated) async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) {
      list[idx] = updated;
      await settings.setProviderConfig(widget.providerKey, old.copyWith(apiKeys: list));
    }
  }

  Future<void> _deleteKey(ApiKeyConfig k) async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == k.id);
    if (idx < 0) return;
    final removed = list.removeAt(idx);
    await settings.setProviderConfig(widget.providerKey, old.copyWith(apiKeys: list));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.multiKeyPageDeleteSnackbarDeletedOne,
      type: NotificationType.info,
      actionLabel: context.l10n.multiKeyPageUndo,
      onAction: () async {
        // Re-insert if user taps undo
        final latest = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
        final cur = List<ApiKeyConfig>.from(latest.apiKeys ?? const <ApiKeyConfig>[]);
        final insertIndex = idx <= cur.length ? idx : cur.length;
        cur.insert(insertIndex, removed);
        await settings.setProviderConfig(widget.providerKey, latest.copyWith(apiKeys: cur));
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: context.l10n.multiKeyPageUndoRestored,
          type: NotificationType.success,
          duration: const Duration(seconds: 2),
        );
      },
    );
  }

  Future<void> _editKey(ApiKeyConfig k) async {
    final updated = await _showEditKeySheet(k);
    if (updated == null) return;
    // Optional: prevent duplicate keys if key changed
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final duplicate = list.any((e) => e.id != k.id && e.key.trim() == updated.key.trim());
    if (duplicate) {
      showAppSnackBar(context, message: context.l10n.multiKeyPageDuplicateKeyWarning, type: NotificationType.warning);
      return;
    }
    await _updateKey(updated);
  }

  Future<void> _onAddKeys() async {
    final l10n = context.l10n;
    final added = await _showAddKeysSheet();
    if (added == null) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final existing = (cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final existingSet = existing.map((e) => e.key.trim()).toSet();
    final unique = <String>[];
    for (final k in added) {
      if (k.isEmpty) continue;
      if (!existingSet.contains(k)) unique.add(k);
    }
    if (unique.isEmpty) {
      showAppSnackBar(context, message: l10n.multiKeyPageImportedSnackbar(0));
      return;
    }
    final newKeys = [
      ...existing,
      for (final s in unique) ApiKeyConfig.create(s),
    ];
    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: newKeys, multiKeyEnabled: true));
    if (!mounted) return;
    showAppSnackBar(context, message: l10n.multiKeyPageImportedSnackbar(unique.length), type: NotificationType.success);

    // Auto-detect imported keys
    await _detectOnly(keys: unique);
  }

  List<String> _splitKeys(String raw) {
    final s = raw.replaceAll(',', ' ').trim();
    return s.split(RegExp(r'\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _onDetect() async {
    if (_detecting) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, message: context.l10n.multiKeyPagePleaseAddModel, type: NotificationType.warning);
        return;
      }
      _detectModelId = models.first;
    }
    setState(() => _detecting = true);
    try {
      await _detectAllForModel(_detectModelId!);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _onPickDetectModel() async {
    final sel = await showModelSelector(context, limitProviderKey: widget.providerKey);
    if (sel != null) {
      setState(() => _detectModelId = sel.modelId);
    }
  }

  Future<void> _onDeleteAllErrorKeys() async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final keys = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final errorKeys = keys.where((e) => e.status == ApiKeyStatus.error).toList();
    if (errorKeys.isEmpty) {
      return;
    }
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.multiKeyPageDeleteErrorsConfirmTitle),
          content: Text(l10n.multiKeyPageDeleteErrorsConfirmContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.multiKeyPageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(l10n.multiKeyPageDelete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final remain = keys.where((e) => e.status != ApiKeyStatus.error).toList();
    await settings.setProviderConfig(widget.providerKey, cfg.copyWith(apiKeys: remain));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.multiKeyPageDeletedErrorsSnackbar(errorKeys.length),
      type: NotificationType.success,
    );
  }

  // ── 弹层 ──────────────────────────────────────────────────

  Future<void> _showStrategySheet() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final current = old.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;

    final selected = await showAppSheet<LoadBalanceStrategy>(
      context: context,
      // 纯选项弹层，不需要跟随键盘/被顶起
      isScrollControlled: false,
      builder: AppSheet(
        children: [
          // Only show Round Robin and Random for now
          for (final s in <LoadBalanceStrategy>[LoadBalanceStrategy.roundRobin, LoadBalanceStrategy.random])
            _strategyOption(
              context,
              label: _strategyLabel(context, s),
              selected: s == current,
              onTap: () => Navigator.of(context).pop(s),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      final km = (old.keyManagement ?? const KeyManagementConfig()).copyWith(strategy: selected);
      await settings.setProviderConfig(widget.providerKey, old.copyWith(keyManagement: km));
    }
  }

  /// 策略选项行：按压只变色不缩放，选中项右侧打勾。
  Widget _strategyOption(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IosTactileRow(
      onTap: onTap,
      builder: (_, pressed) => IosPressColor(
        pressed: pressed,
        base: cs.onSurface,
        builder: (c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGap.md, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
              if (selected) Icon(Icons.check, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<String>?> _showAddKeysSheet() async {
    final l10n = context.l10n;
    final inputCtrl = TextEditingController();
    return showAppSheet<List<String>?>(
      context: context,
      builder: Builder(
        builder: (sheetCtx) => Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _formSheetHeader(sheetCtx, l10n.multiKeyPageAdd),
              const SizedBox(height: AppGap.md),
              _formField(
                sheetCtx,
                controller: inputCtrl,
                hint: l10n.multiKeyPageAddHint,
                minLines: 3,
                maxLines: 6,
              ),
              const SizedBox(height: AppGap.md),
              SizedBox(
                width: double.infinity,
                child: IosTileButton(
                  label: l10n.multiKeyPageAdd,
                  icon: Lucide.Plus,
                  backgroundColor: Theme.of(sheetCtx).colorScheme.primary,
                  onTap: () => Navigator.of(sheetCtx).pop(_splitKeys(inputCtrl.text)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<ApiKeyConfig?> _showEditKeySheet(ApiKeyConfig k) async {
    final l10n = context.l10n;
    final aliasCtrl = TextEditingController(text: k.name ?? '');
    final keyCtrl = TextEditingController(text: k.key);
    final priCtrl = TextEditingController(text: k.priority.toString());
    return showAppSheet<ApiKeyConfig?>(
      context: context,
      builder: Builder(
        builder: (sheetCtx) => Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _formSheetHeader(sheetCtx, l10n.multiKeyPageEdit),
              const SizedBox(height: AppGap.md),
              _formField(sheetCtx, controller: aliasCtrl, hint: l10n.multiKeyPageAlias),
              const SizedBox(height: AppGap.sm),
              _formField(sheetCtx, controller: keyCtrl, hint: l10n.multiKeyPageKey),
              const SizedBox(height: AppGap.sm),
              _formField(
                sheetCtx,
                controller: priCtrl,
                hint: l10n.multiKeyPagePriority,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppGap.md),
              SizedBox(
                width: double.infinity,
                child: IosTileButton(
                  label: l10n.multiKeyPageSave,
                  icon: Lucide.Check,
                  backgroundColor: Theme.of(sheetCtx).colorScheme.primary,
                  onTap: () {
                    final p = int.tryParse(priCtrl.text.trim()) ?? k.priority;
                    final clamped = p.clamp(1, 10);
                    Navigator.of(sheetCtx).pop(
                      k.copyWith(
                        name: aliasCtrl.text.trim().isEmpty ? null : aliasCtrl.text.trim(),
                        key: keyCtrl.text.trim(),
                        priority: clamped,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 表单弹层头部：把手 + 「左关闭 | 居中标题」。
  ///
  /// `AppSheet.title` 只有左对齐一种，套不进这个三段式，故自建。
  Widget _formSheetHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: cs.onSurface.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppRadius.circular),
          ),
        ),
        Row(
          children: [
            IosIconButton(
              haptics: true,
              icon: Lucide.X,
              color: cs.onSurface,
              size: 20,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // 与左侧关闭按钮等宽（20 图标 + 6×2 padding），保证标题真正居中
            const SizedBox(width: 32),
          ],
        ),
      ],
    );
  }

  /// 表单弹层里的输入框：三个字段（别名 / Key / 优先级）形状完全一致。
  Widget _formField(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
    );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
      ),
    );
  }

  // ── 检测 ──────────────────────────────────────────────────

  Future<void> _detectOnly({required List<String> keys}) async {
    final cfg = context.read<SettingsProvider>().getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        showAppSnackBar(context, message: context.l10n.multiKeyPagePleaseAddModel, type: NotificationType.warning);
        return;
      }
      _detectModelId = models.first;
    }
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final toTest = list.where((e) => keys.contains(e.key)).toList();
    await _testKeysAndSave(list, toTest, _detectModelId!);
  }

  Future<void> _detectAllForModel(String modelId) async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    await _testKeysAndSave(list, list, modelId);
  }

  Future<void> _testKeysAndSave(List<ApiKeyConfig> fullList, List<ApiKeyConfig> toTest, String modelId) async {
    final settings = context.read<SettingsProvider>();
    final base = settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final out = List<ApiKeyConfig>.from(fullList);
    for (int i = 0; i < toTest.length; i++) {
      final k = toTest[i];
      final ok = await _testSingleKey(base, modelId, k);
      final idx = out.indexWhere((e) => e.id == k.id);
      if (idx >= 0) out[idx] = k.copyWith(
        status: ok ? ApiKeyStatus.active : ApiKeyStatus.error,
        usage: k.usage.copyWith(
          totalRequests: k.usage.totalRequests + 1,
          successfulRequests: k.usage.successfulRequests + (ok ? 1 : 0),
          failedRequests: k.usage.failedRequests + (ok ? 0 : 1),
          consecutiveFailures: ok ? 0 : (k.usage.consecutiveFailures + 1),
          lastUsed: DateTime.now().millisecondsSinceEpoch,
        ),
        lastError: ok ? null : 'Test failed',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      // Small delay between tests for UX
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await settings.setProviderConfig(widget.providerKey, base.copyWith(apiKeys: out));
  }

  Future<bool> _testSingleKey(ProviderConfig baseCfg, String modelId, ApiKeyConfig key) async {
    try {
      final cfg2 = baseCfg.copyWith(apiKey: key.key);
      await ProviderManager.testConnection(cfg2, modelId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
