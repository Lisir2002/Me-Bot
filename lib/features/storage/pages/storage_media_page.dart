import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/storage_ios_widgets.dart';

/// 媒体型子页面：缩略图网格 + 来源/排序筛选 + 全选 + 多选删除。
class StorageMediaPage extends StatefulWidget {
  const StorageMediaPage({super.key, required this.config, required this.scan});
  final StorageCategoryConfig config;
  final StorageScan scan;

  @override
  State<StorageMediaPage> createState() => _StorageMediaPageState();
}

class _StorageMediaPageState extends State<StorageMediaPage> {
  StorageSource _source = StorageSource.all;
  bool _newest = true;
  bool _largest = false;
  final Set<String> _selected = {};

  List<StorageEntry> get _filtered {
    var list = _source == StorageSource.all
        ? widget.scan.entries
        : widget.scan.entries
            .where((e) => e.source == (_source == StorageSource.user ? 'user' : 'assistant'))
            .toList();
    list = List.of(list);
    if (_largest) {
      list.sort((a, b) => b.bytes.compareTo(a.bytes));
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
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storageDeleteConfirmTitle),
        content: Text(l10n.storageDeleteConfirmBody(_selected.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.storageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.storageConfirmDeleteBtn,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Provider.of<StorageProvider>(context, listen: false)
        .deletePaths(_selected.toList());
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    final items = _filtered;
    final isImage = cfg.id == 'images';

    return Scaffold(
      appBar: AppBar(
        leading: StorageTactileIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(cfg.title),
        actions: [
          StorageTactileIconButton(
            icon: Lucide.RefreshCw,
            color: cs.onSurface,
            size: 20,
            semanticLabel: l10n.storageRefresh,
            onTap: _refresh,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                _InfoHeader(
                  title: cfg.title,
                  bytes: widget.scan.bytes,
                  count: widget.scan.fileCount,
                  caution: cfg.caution,
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _FilterBar(
                    source: _source,
                    newest: _newest,
                    largest: _largest,
                    onSource: (v) => setState(() => _source = v),
                    onOrder: (newest, largest) =>
                        setState(() { _newest = newest; _largest = largest; }),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final selected = _selected.contains(e.path);
                      return _ThumbTile(
                        entry: e,
                        isImage: isImage,
                        selected: selected,
                        onTap: () => _toggleSelect(e.path),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          if (items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.storageSelectedItems(_selected.length),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: StorageFilledButton(
                      icon: Lucide.Trash2,
                      label: l10n.storageDelete,
                      bg: const Color(0xFFFF5F5F),
                      onTap: _selected.isEmpty ? () {} : _confirmDelete,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Text(
                  l10n.storageEmpty,
                  style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  const _InfoHeader({
    required this.title,
    required this.bytes,
    required this.count,
    required this.caution,
  });
  final String title;
  final int bytes;
  final int count;
  final String caution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.06), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                storageFormatBytes(bytes),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.storageItemsCount(count),
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(caution, style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ),
        ],
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
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    Widget segment(List<(String, bool, VoidCallback)> opts) {
      return Row(
        children: [
          for (var i = 0; i < opts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          alignment: Alignment.center,
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
          const SizedBox(height: 4),
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