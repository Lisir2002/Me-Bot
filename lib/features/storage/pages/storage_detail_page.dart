import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_directories.dart';
import '../widgets/storage_ios_widgets.dart';
import 'local_snapshot_page.dart';

/// 只读明细型 / 本地副本型 子页面。
/// 展示：顶部信息（分类名 + 大小 + 文件数 + 风险提示）
///       明细卡片列表（名称 / 大小 · N 个文件 / 完整路径）
/// 本地副本额外提供「管理副本」入口与说明卡。
class StorageDetailPage extends StatefulWidget {
  const StorageDetailPage({super.key, required this.config, required this.scan});
  final StorageCategoryConfig config;
  final StorageScan scan;

  @override
  State<StorageDetailPage> createState() => _StorageDetailPageState();
}

class _StorageDetailPageState extends State<StorageDetailPage> {
  String? _rootPath;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    final dir = await AppDirectories.getAppDataDirectory();
    if (!mounted) return;
    setState(() => _rootPath = dir.path);
  }

  /// 明细条目。助手类始终显示"头像"固定项。
  List<_DetailRowData> _rows(AppLocalizations l10n) {
    final rows = <_DetailRowData>[];
    for (final e in widget.scan.entries) {
      rows.add(_DetailRowData(
        name: e.name,
        bytes: e.bytes,
        path: e.path,
      ));
    }
    if (widget.config.id == 'avatars' && _rootPath != null) {
      rows.add(_DetailRowData(
        name: l10n.storageAvatarItem,
        bytes: 0,
        path: '$_rootPath/avatars',
      ));
    }
    return rows;
  }

  Future<void> _refresh() async =>
      Provider.of<StorageProvider>(context, listen: false).refresh();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    final rows = _rows(l10n);

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
          _InfoHeader(config: cfg, bytes: widget.scan.bytes, count: widget.scan.fileCount),
          if (cfg.type == StorageCategoryType.snapshotDetail && _rootPath != null) ...[
            const SizedBox(height: 12),
            _ManageSnapshotsCard(
              explain: l10n.storageSnapshotPathNote,
              path: '$_rootPath/snapshots',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LocalSnapshotPage()),
              ),
            ),
          ],
          const SizedBox(height: 18),
          StorageSectionHeader(l10n.storageDetailHeader, first: true),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(l10n.storageEmpty, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
              ),
            )
          else
            StorageSectionCard(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const StorageDivider(),
                  _DetailRowTile(row: rows[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailRowData {
  final String name;
  final int bytes;
  final String path;
  const _DetailRowData({required this.name, required this.bytes, required this.path});
}

class _DetailRowTile extends StatelessWidget {
  const _DetailRowTile({required this.row});
  final _DetailRowData row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                storageFormatBytes(row.bytes),
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
              ),
            ],
          ),
          if (row.path.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.path,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// 本地副本 "管理副本" 入口 + 说明卡。
class _ManageSnapshotsCard extends StatelessWidget {
  const _ManageSnapshotsCard({
    required this.explain,
    required this.path,
    required this.onTap,
  });
  final String explain;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = themeDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final cardBorder = storageCardBorder(context);
    return Column(
      children: [
        StorageTactileRow(
          onTap: onTap,
          builder: (_) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: cardBorder,
            ),
            child: Row(
              children: [
                Icon(Lucide.HardDrive, size: 18, color: cs.onSurface.withOpacity(0.7)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.storageManageSnapshots,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: cardBorder,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Lucide.BadgeInfo, size: 14, color: cs.onSurface.withOpacity(0.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      explain,
                      style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurface.withOpacity(0.65)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      path,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.45)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部信息：分类名 + 大小 + 文件数 + 风险提示。
class _InfoHeader extends StatelessWidget {
  const _InfoHeader({required this.config, required this.bytes, required this.count});
  final StorageCategoryConfig config;
  final int bytes;
  final int count;

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
            child: Text(
              config.caution,
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}