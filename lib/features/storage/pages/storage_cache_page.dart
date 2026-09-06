import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_directories.dart';
import '../widgets/storage_ios_widgets.dart';

/// 可清理明细型（缓存）子页面。
/// 顶部两个描边按钮：清理头像缓存 / 清理缓存；下方明细卡。
class StorageCachePage extends StatefulWidget {
  const StorageCachePage({super.key, required this.config});
  final StorageCategoryConfig config;

  @override
  State<StorageCachePage> createState() => _StorageCachePageState();
}

class _StorageCachePageState extends State<StorageCachePage> {
  Future<void> _refresh() async =>
      Provider.of<StorageProvider>(context, listen: false).refresh();

  /// 从实时 Provider 状态取当前分类快照，仅以此作为数据源。
  /// 这是唯一的数据来源，避免持有构造函数传入的冻结快照导致清理后不刷新。
  StorageScan get _scan =>
      context.read<StorageProvider>().scanFor(widget.config.id) ??
      const StorageScan(id: 'none', bytes: 0, fileCount: 0, entries: []);

  Future<void> _clearDirectories(List<String> roots) async {
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _clearAvatar() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storageCacheClearConfirmTitle),
        content: Text(l10n.storageCacheClearConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.storageCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.storageConfirmDeleteBtn, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _clearDirectories([(await AppDirectories.getAvatarCacheDirectory()).path]);
      await _refresh();
    } catch (e, s) {
      debugPrint('[StorageCachePage._clearAvatar] failed: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  Future<void> _clearApp() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storageCacheClearConfirmTitle),
        content: Text(l10n.storageCacheClearConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.storageCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.storageConfirmDeleteBtn, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _clearDirectories([(await AppDirectories.getCacheDirectory()).path]);
      await _refresh();
    } catch (e, s) {
      debugPrint('[StorageCachePage._clearApp] failed: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    context.watch<StorageProvider>();
    final scan = _scan;

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _InfoHeader(config: cfg, scan: scan),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StorageOutlineButton(
                  icon: Lucide.ImageOff,
                  label: l10n.storageCacheClearAvatar,
                  onTap: _clearAvatar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StorageOutlineButton(
                  icon: Lucide.ZapOff,
                  label: l10n.storageCacheClearApp,
                  onTap: _clearApp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          StorageSectionHeader(l10n.storageDetailHeader, first: true),
          const SizedBox(height: 6),
          if (scan.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(l10n.storageEmpty, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
              ),
            )
          else
            StorageSectionCard(
              children: [
                for (var i = 0; i < scan.entries.length; i++) ...[
                  if (i > 0) const StorageDivider(),
                  _CacheRow(entry: scan.entries[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.entry});
  final StorageEntry entry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  entry.path,
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            storageFormatBytes(entry.bytes),
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  const _InfoHeader({required this.config, required this.scan});
  final StorageCategoryConfig config;
  final StorageScan scan;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: storageCardBorder(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                storageFormatBytes(scan.bytes),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.storageItemsCount(scan.fileCount),
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.storageCleanableNote,
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}