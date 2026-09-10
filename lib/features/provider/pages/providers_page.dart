// no_raw_alert_dialog 白名单：现有弹窗待迁移到 AppDialog
// no_manual_listview_padding 白名单：现有页面内部 ListView 待迁移到 AppListView
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/brand_assets.dart';
import '../../../icons/lucide_adapter.dart';
import 'provider_detail_page.dart';
import '../widgets/import_provider_sheet.dart';
import '../widgets/add_provider_sheet.dart';
// grid reorder removed in favor of iOS-style list reordering
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../widgets/share_provider_sheet.dart';
import '../../../core/providers/assistant_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'dart:ui' as ui show ImageFilter;
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../theme/design_tokens.dart';
import '../../../core/services/security/app_lock_gate.dart';
import '../../../core/services/security/app_lock_service.dart';
import '../../../core/services/security/clipboard_guard.dart';
import '../../../core/services/security/credential_audit_logger.dart';

// ──────────────────────────────────────────────────────────────
// 迁移到 AppPage 骨架（批次 3 收官页，1123 行 → ~950 行）
//
// 骨架层：
//   Scaffold + AppBar + Stack        → AppPage.selfScrolling(title / actions / body)
//   AppBar leading 的私有返回按钮      → AppPage 默认 showBack（44pt 热区）
//   ⚠️ safeArea: false               —— 本页自己用 `MediaQuery.padding.bottom`
//                                      手动给列表留出系统栏空间（列表要"贴底"，
//                                      底栏还是浮层），引擎再包一层 SafeArea 会二次叠加
//   ⚠️ scrollable: false             —— 内容是 `ReorderableListView`，自带滚动（清单 3c）
//   ⚠️ bodyPadding: zero             —— `_ProvidersList` 自带 `fromLTRB(16, 8, 16, 0)`
//   Stack + Positioned 浮层           —— **不用 `bottom:` 槽位**：它会变成
//                                      bottomNavigationBar 常驻占位并把 body 顶上去，
//                                      而选择栏是「滑入/滑出」的浮层
//
// 组件层：
//   _TactileIconButton（4 处 AppBar）  → IosIconButton(haptics: true, minSize: 44)
//   _TactileRow（供应商行）            → IosTactileRow(haptics: false)（触觉由 onTap 内按需触发）
//   _AnimatedPressColor               → IosPressColor
//   _showMultiExportSheet             → showAppSheet（把手 + 居中标题，故内容自建）
//
// 顺带清理：`settings_provider.dart` import 两遍；4 处死代码——
//   `_items` 字段（声明后从未读写）、`_CapsuleButton`（65 行，无调用点）、
//   `_Pill`（17 行）、`_DragHandle`（32 行，注释已写"drag handle removed"）。
//
// 仍留在本地的私有件：
//   _ProvidersList —— 卡片的圆角会随「是否触底」变化（触底则下缘拉直），是独一份的形状
//   _iosDivider    —— 与 `SettingsDivider` 默认值逐值相同，但 provider 不便反向依赖
//                     features/settings（同 `_iosSectionCard`，见迁移计划「待办 F」）
//   _GlassCircleButton / _SettleAnim / _BrandAvatar / _IconAsset —— 视觉语义独一份
// ──────────────────────────────────────────────────────────────

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  final Set<String> _settleKeys = {};
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    // Base, fixed providers (recompute each build so dynamic additions reflect immediately)
    final base = _providers(l10n: l10n);

    // Dynamic providers from settings
    final settings = context.watch<SettingsProvider>();
    final cfgs = settings.providerConfigs;
    final baseKeys = {for (final p in base) p.keyName};
    final dynamicItems = <_Provider>[];
    cfgs.forEach((key, cfg) {
      if (!baseKeys.contains(key)) {
        dynamicItems.add(_Provider(
          name: (cfg.name.isNotEmpty ? cfg.name : key),
          keyName: key,
          enabled: cfg.enabled,
          modelCount: cfg.models.length,
        ));
      }
    });

    // Merge base + dynamic, then apply saved order
    final merged = <_Provider>[...base, ...dynamicItems];
    final order = settings.providersOrder;
    final map = {for (final p in merged) p.keyName: p};
    final tmp = <_Provider>[];
    for (final k in order) {
      final p = map.remove(k);
      if (p != null) tmp.add(p);
    }
    // Append any remaining providers not recorded in order
    tmp.addAll(map.values);
    final items = tmp;

    return AppPage.selfScrolling(
      title: l10n.providersPageTitle,
      // 见文件头注释：本页自己处理系统栏，关掉引擎的 SafeArea 避免二次叠加
      safeArea: false,
      // 见文件头注释：ReorderableListView 自带滚动
      actions: [
        Tooltip(
          message: _selectMode ? l10n.searchServicesPageDone : l10n.providersPageMultiSelectTooltip,
          child: IosIconButton(
            haptics: true,
            icon: _selectMode ? Lucide.Check : Lucide.circleDot,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            onTap: () {
              setState(() {
                if (_selectMode) {
                  _selected.clear();
                }
                _selectMode = !_selectMode;
              });
            },
          ),
        ),
        Tooltip(
          message: l10n.providersPageImportTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.cloudDownload,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            onTap: () async {
              await showImportProviderSheet(context);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ),
        Tooltip(
          message: l10n.providersPageAddTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            onTap: () async {
              final createdKey = await showAddProviderSheet(context);
              if (!mounted) return;
              if (createdKey != null && createdKey.isNotEmpty) {
                setState(() {});
                final msg = l10n.providersPageProviderAddedSnackbar;
                showAppSnackBar(
                  context,
                  message: msg,
                  type: NotificationType.success,
                );
              }
            },
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      // 选择栏是「滑入/滑出」的浮层，必须盖在列表之上，
      // 因此这里用 Stack + Positioned，而不是 `bottom:` 槽位（后者会常驻占位）。
      body: Stack(
        children: [
          _ProvidersList(
            items: items,
            selectMode: _selectMode,
            selectedKeys: _selected,
            onToggleSelect: (key) {
              setState(() {
                if (_selected.contains(key)) {
                  _selected.remove(key);
                } else {
                  _selected.add(key);
                }
              });
            },
            onReorder: (oldIndex, newIndex) async {
              // Normalize newIndex because Flutter passes the index after removal
              if (newIndex > oldIndex) newIndex -= 1;
              final moved = items[oldIndex];
              final mut = List<_Provider>.of(items);
              final item = mut.removeAt(oldIndex);
              mut.insert(newIndex, item);
              setState(() => _settleKeys.add(moved.keyName));
              await context.read<SettingsProvider>().setProvidersOrder([
                for (final p in mut) p.keyName
              ]);
              Future.delayed(const Duration(milliseconds: 220), () {
                if (!mounted) return;
                setState(() => _settleKeys.remove(moved.keyName));
              });
            },
            settlingKeys: _settleKeys,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SelectionBar(
              visible: _selectMode,
              count: _selected.length,
              total: items.length,
              onExport: _onExportSelected,
              onDelete: _onDeleteSelected,
              onSelectAll: () {
                setState(() {
                  // Select all deletable (non-built-in) providers
                  final baseKeys = {for (final p in base) p.keyName};
                  final deletable = [for (final p in items) if (!baseKeys.contains(p.keyName)) p.keyName];
                  final allSelected = deletable.isNotEmpty && deletable.every(_selected.contains) && _selected.length == deletable.length;
                  _selected.removeWhere((k) => !deletable.contains(k));
                  if (allSelected) {
                    // Unselect all deletable
                    for (final k in deletable) { _selected.remove(k); }
                  } else {
                    // Select all deletable
                    _selected
                      ..removeWhere((k) => !deletable.contains(k))
                      ..addAll(deletable);
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_Provider> _providers({required AppLocalizations l10n}) => [
        _p('OpenAI', 'OpenAI', enabled: true, models: 0),
        _p(l10n.providersPageSiliconFlowName, 'SiliconFlow', enabled: true, models: 0),
        _p('Gemini', 'Gemini', enabled: true, models: 0),
        _p('OpenRouter', 'OpenRouter', enabled: true, models: 0),
        _p('MiniMeCoreIN', 'MiniMeCoreIN', enabled: true, models: 0),
        _p('Tensdaq', 'Tensdaq', enabled: false, models: 0),
        _p('DeepSeek', 'DeepSeek', enabled: false, models: 0),
        _p(l10n.providersPageAliyunName, 'Aliyun', enabled: false, models: 0),
        _p(l10n.providersPageZhipuName, 'Zhipu AI', enabled: false, models: 0),
        _p('Claude', 'Claude', enabled: false, models: 0),
        // _p(zh ? '腾讯混元' : 'Hunyuan', 'Hunyuan', enabled: false, models: 0),
        // _p('InternLM', 'InternLM', enabled: true, models: 0),
        // _p('Kimi', 'Kimi', enabled: false, models: 0),
        _p('Grok', 'Grok', enabled: false, models: 0),
        // _p('302.AI', '302.AI', enabled: false, models: 0),
        // _p(zh ? '阶跃星辰' : 'StepFun', 'StepFun', enabled: false, models: 0),
        // _p('MiniMax', 'MiniMax', enabled: true, models: 0),
        _p(l10n.providersPageByteDanceName, 'ByteDance', enabled: false, models: 0),
        // _p(zh ? '豆包' : 'Doubao', 'Doubao', enabled: true, models: 0),
        // _p(zh ? '阿里云' : 'Alibaba Cloud', 'Alibaba Cloud', enabled: true, models: 0),
        // _p('Meta', 'Meta', enabled: false, models: 0),
        // _p('Mistral', 'Mistral', enabled: true, models: 0),
        // _p('Perplexity', 'Perplexity', enabled: true, models: 0),
        // _p('Cohere', 'Cohere', enabled: true, models: 0),
        // _p('Gemma', 'Gemma', enabled: true, models: 0),
        // _p('Cloudflare', 'Cloudflare', enabled: true, models: 0),
        //  _p('AIHubMix', 'AIHubMix', enabled: false, models: 0),
        // _p('Ollama', 'Ollama', enabled: true, models: 0),
        // _p('GitHub', 'GitHub', enabled: false, models: 0),
      ];

  _Provider _p(String name, String key, {required bool enabled, required int models}) =>
      _Provider(name: name, keyName: key, enabled: enabled, modelCount: models);

  Future<void> _onExportSelected() async {
    if (_selected.isEmpty) return;
    final keys = _selected.toList(growable: false);
    if (keys.length == 1) {
      await showShareProviderSheet(context, keys.first);
      return;
    }
    await _showMultiExportSheet(context, keys);
  }

  Future<void> _onDeleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = context.l10n;
    // Skip built-in providers (default ones)
    final builtInKeys = {for (final p in _providers(l10n: l10n)) p.keyName};
    final keysToDelete = _selected.where((k) => !builtInKeys.contains(k)).toList(growable: false);

    if (keysToDelete.isEmpty) {
      // Nothing deletable selected
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.providerDetailPageDeleteProviderTitle} (${keysToDelete.length})'),
        content: Text(l10n.providersPageDeleteSelectedConfirmContent),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.providerDetailPageCancelButton)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.providerDetailPageDeleteButton, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // 尽可能复用 ProviderDetailPage 删除前的清理逻辑：清理引用该 provider 的助手模型选择
      try {
        final ap = context.read<AssistantProvider>();
        for (final a in ap.assistants) {
          if (keysToDelete.contains(a.chatModelProvider)) {
            await ap.updateAssistant(a.copyWith(clearChatModel: true));
          }
        }
      } catch (_) {}
      final sp = context.read<SettingsProvider>();
      for (final k in keysToDelete) {
        await sp.removeProviderConfig(k);
      }
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      showAppSnackBar(context, message: l10n.providersPageDeleteSelectedSnackbar, type: NotificationType.success);
    } catch (_) {}
  }
}

// iOS-style providers list (reorderable by long-press)
class _ProvidersList extends StatelessWidget {
  const _ProvidersList({
    required this.items,
    required this.onReorder,
    required this.settlingKeys,
    required this.selectMode,
    required this.selectedKeys,
    required this.onToggleSelect,
  });
  final List<_Provider> items;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Set<String> settlingKeys;
  final bool selectMode;
  final Set<String> selectedKeys;
  final void Function(String key) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06);

    // Adapt height: wrap to content if short; flush to bottom if long
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.xs, AppGap.md, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final safeBottom = media.padding.bottom;
          final bottomGapIfFlush = safeBottom + 16.0; // leave room above system bar

          final maxH = constraints.hasBoundedHeight ? constraints.maxHeight : double.infinity;
          // Estimate row height: avatar(22) + vertical paddings(11*2) ~= 44
          const double rowH = 44.0;
          const double dividerH = 6.0; // _iosDivider height
          const double listPadV = 8.0; // ReorderableListView vertical padding
          final int n = items.length;
          final double baseContentH = n == 0 ? 0.0 : (n * rowH + (n - 1) * dividerH + listPadV);
          // Decide if we should treat it as reaching bottom (considering the bottom gap we will add)
          final bool reachesBottom = maxH.isFinite &&
              (baseContentH >= maxH - 0.5 || (baseContentH + bottomGapIfFlush) >= maxH - 0.5);
          final double effectiveContentH = baseContentH + (reachesBottom ? bottomGapIfFlush : 0.0);
          final double containerH = maxH.isFinite ? (effectiveContentH.clamp(0.0, maxH)).toDouble() : effectiveContentH;

          return Container(
            height: containerH.isFinite ? containerH : null,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
                // If not reaching bottom, use rounded corners; if reaching bottom, flush
                bottomLeft: Radius.circular(reachesBottom ? 0 : AppRadius.md),
                bottomRight: Radius.circular(reachesBottom ? 0 : AppRadius.md),
              ),
              border: Border.all(color: borderColor, width: 0.6),
            ),
            clipBehavior: Clip.antiAlias,
            child: ReorderableListView.builder(
              padding: EdgeInsets.only(top: AppGap.xxs, bottom: reachesBottom ? bottomGapIfFlush : AppGap.xxs),
              itemCount: items.length,
              onReorder: onReorder,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Opacity(
                opacity: 0.95,
                child: Transform.scale(scale: 0.98, child: child),
              ),
              itemBuilder: (context, index) {
                final p = items[index];
                return KeyedSubtree(
                  key: ValueKey(p.keyName),
                  child: _SettleAnim(
                    active: settlingKeys.contains(p.keyName),
                    child: _ProviderRow(
                      provider: p,
                      index: index,
                      total: items.length,
                      selectMode: selectMode,
                      selected: selectedKeys.contains(p.keyName),
                      onToggleSelect: onToggleSelect,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.index,
    required this.total,
    required this.selectMode,
    required this.selected,
    required this.onToggleSelect,
  });
  final _Provider provider;
  final int index;
  final int total;
  final bool selectMode;
  final bool selected;
  final void Function(String key) onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(provider.keyName, defaultName: provider.name);
    final enabled = cfg.enabled;
    final l10n = context.l10n;

    final statusBg = enabled ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.15);
    final statusFg = enabled ? Colors.green : Colors.orange;

    final isLast = index == total - 1;

    // pressedScale 不传 = 不缩放（对上原来的 1.00）；
    // haptics: false —— 触觉由 onTap 内按「是否选择模式」决定是否触发，
    // 而 IosTactileRow 的触觉开关是「列表项点按」全局设置，语义不同。
    final row = IosTactileRow(
      onTap: () {
        if (selectMode) {
          Haptics.light();
          onToggleSelect(provider.keyName);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderDetailPage(
                keyName: provider.keyName,
                displayName: provider.name,
              ),
            ),
          );
        }
      },
      haptics: false,
      builder: (ctx, pressed) {
        return IosPressColor(
          pressed: pressed,
          base: cs.onSurface.withOpacity(0.9),
          builder: (color) {
            final rowContent = Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Row(
                  children: [
                  // Animated appear of select dot area with width transition
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: selectMode ? 28 : 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: selectMode ? 1.0 : 0.0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IosCheckbox(
                          value: selected,
                          size: 20,
                          hitTestSize: 22,
                          borderWidth: 1.6,
                          activeColor: cs.primary,
                          borderColor: cs.onSurface.withOpacity(0.35),
                          onChanged: (_) => onToggleSelect(provider.keyName),
                        ),
                      ),
                    ),
                  ),
                  if (selectMode) const SizedBox(width: AppGap.xxs),
                  SizedBox(width: 36, child: Center(child: _BrandAvatar(name: (cfg.name.isNotEmpty ? cfg.name : provider.keyName), size: 22))),
                  const SizedBox(width: AppGap.sm),
                  Expanded(
                    child: Text(
                      (cfg.name.isNotEmpty ? cfg.name : provider.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppGap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(AppRadius.circular),
                    ),
                    child: Text(
                      enabled ? l10n.providersPageEnabledStatus : l10n.providersPageDisabledStatus,
                      style: TextStyle(fontSize: 11, color: statusFg),
                    ),
                  ),
                  const SizedBox(width: AppGap.xs),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
                    child: selectMode
                        ? const SizedBox.shrink(key: ValueKey('none'))
                        : Icon(Lucide.ChevronRight, size: 16, color: color, key: const ValueKey('chev')),
                  ),
                ],
              ),
              ));

            Widget line = KeyedSubtree(key: ValueKey('row-$index'), child: rowContent);
            if (!selectMode) {
              line = ReorderableDelayedDragStartListener(index: index, child: line);
            }
            return Column(children: [line, if (!isLast) _iosDivider(ctx)]);
          },
        );
      },
    );

    // Return row directly; container card background is provided by the wrapper
    // so dragged-out slot shows card color instead of page background.
    return row;
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.visible,
    required this.count,
    required this.total,
    required this.onExport,
    required this.onDelete,
    required this.onSelectAll,
  });
  final bool visible;
  final int count;
  final int total;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !visible,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.md, 10, AppGap.md, 46),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlassCircleButton(
                      icon: Lucide.Trash2,
                      color: const Color(0xFFFF3B30),
                      semanticLabel: l10n.providersPageDeleteAction,
                      onTap: onDelete,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.checkCheck,
                      color: cs.primary,
                      semanticLabel: null,
                      onTap: onSelectAll,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.Share2,
                      color: cs.primary,
                      semanticLabel: l10n.providersPageExportAction,
                      onTap: onExport,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 46, // ignore: unused_element_parameter
    this.semanticLabel,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size; // diameter
  final String? semanticLabel;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}


class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase = isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.06);
    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.10 : 0.10);

    final child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: Container(
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showMultiExportSheet(BuildContext context, List<String> keys) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final l10n = context.l10n;
  final entries = [
    for (final k in keys)
      () {
        final cfg = settings.providerConfigs[k] ?? settings.getProviderConfig(k);
        final name = (cfg.name.isNotEmpty ? cfg.name : k);
        final code = encodeProviderConfig(cfg);
        return {'name': name, 'code': code};
      }()
  ];
  final text = entries.map((e) => e['code']).join('\n');
  // 自建内容：标题居中，`AppSheet.title` 只有左对齐一种，套不进去（把手需自己画）。
  // SafeArea + 键盘避让由 showAppSheet 统一处理，故去掉手写的 viewInsets.bottom。
  await showAppSheet<void>(
    context: context,
    builder: Builder(
      builder: (ctx) {
        final bool showQr = keys.length <= 4;
        Rect shareAnchorRect(BuildContext bctx) {
          try {
            final ro = bctx.findRenderObject();
            if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
              final origin = ro.localToGlobal(Offset.zero);
              return origin & ro.size;
            }
          } catch (_) {}
          final size = MediaQuery.of(bctx).size;
          return Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
        }
        return Padding(
          // 10 无精确 token（xs=8 / sm=12），保留字面量
          padding: const EdgeInsets.fromLTRB(AppGap.md, 10, AppGap.md, AppGap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(AppRadius.circular),
                  ),
                ),
              ),
              const SizedBox(height: AppGap.sm),
              Center(
                child: Text(
                  l10n.providersPageExportSelectedTitle(keys.length),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: AppGap.sm),
              // Show QR only when selection is small to avoid overlong input
              if (showQr) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                    ),
                    child: PrettyQr(
                      data: text,
                      size: 180,
                      roundEdges: true,
                      errorCorrectLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),
                const SizedBox(height: AppGap.sm),
              ],
              // Limited preview of codes (6-7 lines), full content still copied/shared
              SizedBox(
                height: 128,
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ),
              ),
              const SizedBox(height: AppGap.sm),
              Row(
                children: [
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Copy,
                      label: l10n.providersPageExportCopyButton,
                      onTap: () async {
                        // PR-5/PR-6：导出内容含 apiKey（base64），复制前过隐私门禁，
                        // 复制后由 ClipboardGuard 60s 自动清除，并留审计。
                        final lock = AppLockService.instance ??
                            await AppLockService.load();
                        if (!await lock.ensureUnlocked(LockAction.copyCredential,
                            context: context)) {
                          CredentialAuditLogger.record(
                              'copy', 'provider:export', ok: false);
                          return;
                        }
                        await ClipboardGuard.instance.guard(text);
                        CredentialAuditLogger.record(
                            'copy', 'provider:export(${keys.length})');
                        if (!context.mounted) return;
                        showAppSnackBar(context, message: l10n.providersPageExportCopiedSnackbar, type: NotificationType.success);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Share2,
                      label: l10n.providersPageExportShareButton,
                      onTap: () async {
                        final rect = shareAnchorRect(ctx);
                        await Share.share(text, subject: 'AI Providers', sharePositionOrigin: rect);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

// Drag handle removed per design; dragging is triggered by long-pressing the card.

// Replaced custom reorder grid with reorderable_grid_view for
// smoother, battle-tested drag animations and reordering.

class _SettleAnim extends StatelessWidget {
  const _SettleAnim({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tween = Tween<double>(begin: active ? 0.94 : 1.0, end: 1.0);
    return TweenAnimationBuilder<double>(
      tween: tween,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, scale, _) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: 1.0,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 40});
  final String name;
  final double size;

  bool _preferMonochromeWhite(String n) {
    final k = n.toLowerCase();
    if (RegExp(r'openai|gpt|o\d').hasMatch(k)) return true;
    if (RegExp(r'grok|xai').hasMatch(k)) return true;
    if (RegExp(r'openrouter').hasMatch(k)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: asset == null
          ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42))
          : _IconAsset(
              asset: asset,
              size: size * 0.62,
              monochromeWhite: isDark && _preferMonochromeWhite(name),
            ),
    );
    return circle;
  }
}

class _IconAsset extends StatelessWidget {
  const _IconAsset({required this.asset, required this.size, this.monochromeWhite = false});
  final String asset;
  final double size;
  final bool monochromeWhite;
  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: monochromeWhite
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null,
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: monochromeWhite ? Colors.white : null,
      colorBlendMode: monochromeWhite ? BlendMode.srcIn : null,
    );
  }
}

class _Provider {
  final String name;
  final String keyName;
  final bool enabled;
  final int modelCount;
  _Provider({required this.name, required this.keyName, required this.enabled, required this.modelCount});
}

/// 行间分隔线。与 `SettingsDivider` 的默认值逐值相同（height 6 / thickness 0.6 /
/// indent 54 / endIndent 12），但 provider 不便反向依赖 features/settings，
/// 故本地保留（全仓统一收敛见迁移计划「待办 F」）。
Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 6, thickness: 0.6, indent: 54, endIndent: AppGap.sm, color: cs.outlineVariant.withOpacity(0.18));
}
