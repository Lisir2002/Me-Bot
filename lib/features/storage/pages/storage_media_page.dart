import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../core/services/logging/logger.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_list_view.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/storage_ios_widgets.dart';
import '../widgets/storage_info_header.dart';
import '../../../shared/widgets/snackbar.dart';

/// 可作为缩略图渲染的图片扩展名（与 StorageService 的图片集合保持一致）。
const Set<String> _thumbImageExtensions = {
  '.png', '.jpg', '.jpeg', '.webp', '.gif',
  '.heic', '.heif', '.bmp', '.tiff', '.tif', '.avif',
};

/// 按文件自身类型判断是否可渲染缩略图，而非按所属分类一刀切。
bool _isThumbImage(StorageEntry e) {
  final lower = e.name.toLowerCase();
  return _thumbImageExtensions.any(lower.endsWith);
}

/// 媒体型子页面：缩略图网格 + 来源/排序筛选 + 全选 + 多选删除。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + Column[Expanded(ListView), 底部操作条]
///   → AppPage.selfScrolling(body: ListView, bottom: 操作条)
///   —— 这是本批次第一个真正用上 `bottom:` 槽位的页面：底部"全选/删除"操作条
///      原来靠 Expanded + Column 撑在列表下方，现在由引擎固定到底栏区。
/// - scrollable: false —— 引擎的 scrollable 用的是 ListView(children:[body])，会给子内容
///   **无界高度**；本页 body 自带 ListView 需要撑满剩余空间，因此必须关掉引擎滚动。
/// - bodyPadding: zero —— padding 交给内部 ListView 自带（保持与原实现一致的滚动内缩视觉）
/// - 空态 → 居中 AppEmpty（同时 bottom 传 null，与原来"空态不显示底栏"一致）
/// - debugPrint → Logger.e（审计 P2-01）
/// - 底部操作条补 SafeArea(top: false)：原实现全页无 SafeArea，iOS 机型上删除按钮会被
///   home indicator 压住；AppPage 只对 body 加 SafeArea，底栏不在其中，故单独补。
class StorageMediaPage extends StatefulWidget {
  const StorageMediaPage({super.key, required this.config});
  final StorageCategoryConfig config;

  @override
  State<StorageMediaPage> createState() => _StorageMediaPageState();
}

class _StorageMediaPageState extends State<StorageMediaPage> {
  StorageSource _source = StorageSource.all;
  bool _newest = true;
  bool _largest = false;
  final Set<String> _selected = {};

  /// 从实时 Provider 状态取当前分类快照，仅以此作为数据源。
  /// 这是唯一的数据来源，避免持有构造函数传入的冻结快照导致删除后不刷新。
  StorageScan get _scan =>
      context.read<StorageProvider>().scanFor(widget.config.id) ??
      const StorageScan(id: 'none', bytes: 0, fileCount: 0, entries: []);

  List<StorageEntry> _filteredFor(StorageScan scan) {
    var list = _source == StorageSource.all
        ? scan.entries
        : scan.entries
            .where((e) => e.source == (_source == StorageSource.user ? 'user' : 'assistant'))
            .toList();
    list = List.of(list);
    if (_largest) {
      // 按大小排序时，_newest 语义为「降序」：最大优先=true，最小优先=false。
      // 原实现恒为降序，导致「最小优先」按钮点了没反应。
      list.sort((a, b) => _newest
          ? b.bytes.compareTo(a.bytes)
          : a.bytes.compareTo(b.bytes));
    } else {
      list.sort((a, b) => _newest
          ? (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0))
          : (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0)));
    }
    return list;
  }

  Future<void> _refresh() async =>
      Provider.of<StorageProvider>(context, listen: false).refresh();

  void _toggleSelect(String path) {
    setState(() {
      if (!_selected.add(path)) _selected.remove(path);
    });
  }

  Future<void> _confirmDelete() async {
    try {
      final l10n = context.l10n;
      final ok = await AppDialog.confirm(
        context,
        title: l10n.storageDeleteConfirmTitle,
        message: l10n.storageDeleteConfirmBody(_selected.length),
        confirmText: l10n.storageConfirmDeleteBtn,
        cancelText: l10n.storageCancel,
        danger: true,
      );
      if (ok != true || !mounted) return;
      await Provider.of<StorageProvider>(context, listen: false)
          .deletePaths(_selected.toList());
      if (!mounted) return;
      setState(() => _selected.clear());
    } catch (e, s) {
      Logger.e('StorageMedia', 'delete selected failed', e, s);
      if (mounted) {
        showAppSnackBar(context,
            message: context.l10n.deleteFailed(e.toString()), type: NotificationType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    context.watch<StorageProvider>();
    final scan = _scan;
    final items = _filteredFor(scan);

    return AppPage.selfScrolling(
      title: cfg.title,
      leading: StorageTactileIconButton(
        icon: Lucide.ArrowLeft,
        color: cs.onSurface,
        size: 22,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        StorageTactileIconButton(
          icon: Lucide.RefreshCw,
          color: cs.onSurface,
          size: 20,
          semanticLabel: l10n.storageRefresh,
          onTap: _refresh,
        ),
        const SizedBox(width: AppGap.sm),
      ],
      body: items.isEmpty
          ? Center(child: AppEmpty(message: l10n.storageEmpty))
          : AppListView(
              topPadding: AppGap.sm,
              bottomPadding: AppGap.sm,
              children: [
                StorageInfoHeader(
                  title: cfg.title,
                  bytes: scan.bytes,
                  count: scan.fileCount,
                  note: cfg.caution,
                ),
                const SizedBox(height: AppGap.sm),
                _FilterBar(
                  source: _source,
                  newest: _newest,
                  largest: _largest,
                  onSource: (v) => setState(() => _source = v),
                  onOrder: (newest, largest) =>
                      setState(() { _newest = newest; _largest = largest; }),
                ),
                const SizedBox(height: AppGap.sm),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: AppGap.xs,
                    crossAxisSpacing: AppGap.xs,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final selected = _selected.contains(e.path);
                    return _ThumbTile(
                      entry: e,
                      // 按文件自身类型判断是否可渲染缩略图。
                      // 原实现按分类 id 判断（images/avatars 全当图片），
                      // 导致「助手」分类里的非图片文件（后续接入 agent 工作区
                      // 会有各类文件）也被当成图片去解码。
                      isImage: _isThumbImage(e),
                      selected: selected,
                      onTap: () => _toggleSelect(e.path),
                    );
                  },
                ),
                const SizedBox(height: AppGap.sm),
              ],
            ),
      bottom: items.isEmpty
          ? null
          : SafeArea(
              top: false,
              // stretch 必需：Row 里有 Expanded，需要子项拿到有界宽度。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppGap.md, AppGap.xxs, AppGap.md, AppGap.xxxs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.storageSelectedItems(_selected.length),
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppGap.md, 0, AppGap.md, AppGap.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: StorageOutlineButton(
                            icon: Lucide.CheckSquare,
                            label: l10n.storageSelectAll,
                            onTap: () {
                              setState(() {
                                if (_selected.length == items.length) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(items.map((e) => e.path));
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: AppGap.sm),
                        Expanded(
                          child: StorageFilledButton(
                            icon: Lucide.Trash2,
                            label: l10n.storageDelete,
                            bg: const Color(0xFFFF5F5F),
                            // 保持原语义：未选中时给空回调而非禁用。
                            // TODO(优化)：若 StorageFilledButton.onTap 改为可空，这里传
                            // `_selected.isEmpty ? null : _confirmDelete` 更规范（按钮自动置灰）。
                            onTap: _selected.isEmpty ? () {} : _confirmDelete,
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

class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.source,
    required this.newest,
    required this.largest,
    required this.onSource,
    required this.onOrder,
  });
  final StorageSource source;
  final bool newest;
  final bool largest;
  final ValueChanged<StorageSource> onSource;
  final void Function(bool newest, bool largest) onOrder;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    Widget segment(List<(String, bool, VoidCallback)> opts) {
      return Row(
        children: [
          for (var i = 0; i < opts.length; i++) ...[
            if (i > 0) const SizedBox(width: AppGap.xs),
            Expanded(child: _SegmentButton(
              label: opts[i].$1,
              active: opts[i].$2,
              onTap: opts[i].$3,
            )),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.storageSource, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
        const SizedBox(height: 6),
        segment([
          (l10n.storageSourceAll, widget.source == StorageSource.all, () => widget.onSource(StorageSource.all)),
          (l10n.storageSourceUser, widget.source == StorageSource.user, () => widget.onSource(StorageSource.user)),
          (l10n.storageSourceAssistant, widget.source == StorageSource.assistant, () => widget.onSource(StorageSource.assistant)),
        ]),
        const SizedBox(height: 10),
        Text(l10n.storageOrder, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
        const SizedBox(height: 6),
        segment([
          (l10n.storageOrderNewest, !widget.largest && widget.newest, () => widget.onOrder(true, false)),
          (l10n.storageOrderOldest, !widget.largest && !widget.newest, () => widget.onOrder(false, false)),
          (l10n.storageOrderLargest, widget.largest && widget.newest, () => widget.onOrder(true, true)),
          (l10n.storageOrderSmallest, widget.largest && !widget.newest, () => widget.onOrder(false, true)),
        ]),
      ],
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.active
        ? (themeDark ? cs.primary.withOpacity(0.25) : cs.primary.withOpacity(0.12))
        : (themeDark ? Colors.white10 : const Color(0xFFF7F7F9));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => setState(() => _pressed = false)),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: AppGap.xxs),
          alignment: Alignment.center,
          // 9 无精确 token，保留字面量
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
              color: widget.active ? cs.primary : cs.onSurface.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.entry,
    required this.isImage,
    required this.selected,
    required this.onTap,
  });
  final StorageEntry entry;
  final bool isImage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            // 10 无精确 token（AppRadius.sm=8 / md=12），保留字面量
            borderRadius: BorderRadius.circular(10),
            child: isImage
                ? Image.file(File(entry.path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _Fallback(entry: entry))
                : _Fallback(entry: entry),
          ),
          if (selected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary, width: 2),
                ),
              ),
            ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? cs.primary : cs.surface.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: selected ? cs.primary : cs.outline, width: 1.5),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Icon(Lucide.Check, size: 13, color: cs.onPrimary)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.entry});
  final StorageEntry entry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest.withOpacity(0.5),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Lucide.FileText, size: 26, color: cs.onSurface.withOpacity(0.5)),
          const SizedBox(height: AppGap.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
