import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_directories.dart';
import '../widgets/storage_ios_widgets.dart';
import '../widgets/storage_info_header.dart';
import 'local_snapshot_page.dart';

/// 只读明细型 / 本地副本型 子页面。
/// 展示：顶部信息（分类名 + 大小 + 文件数 + 风险提示）
///       明细卡片列表（名称 / 大小 · N 个文件 / 完整路径）
/// 本地副本额外提供「管理副本」入口与说明卡。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/actions/body)
/// - padding LTRB(16,12,16,24) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl)
/// - 空态 → AppEmpty
class StorageDetailPage extends StatefulWidget {
  const StorageDetailPage({super.key, required this.config});
  final StorageCategoryConfig config;

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

  /// 从实时 Provider 状态取当前分类快照，仅以此作为数据源。
  /// 这是唯一的数据来源，避免持有构造函数传入的冻结快照导致清理后不刷新。
  StorageScan get _scan =>
      context.read<StorageProvider>().scanFor(widget.config.id) ??
      const StorageScan(id: 'none', bytes: 0, fileCount: 0, entries: []);

  /// 明细条目。助手类始终显示"头像"固定项。
  List<_DetailRowData> _rows(AppLocalizations l10n, StorageScan scan) {
    final rows = <_DetailRowData>[];
    for (final e in scan.entries) {
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
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    context.watch<StorageProvider>();
    final scan = _scan;
    final rows = _rows(l10n, scan);

    return AppPage(
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
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl),
      // crossAxisAlignment.stretch 必需：AppPage 的滚动容器给子项紧宽度，
      // 但 Column 默认 center 会把宽度放宽，卡片会缩成内容宽度。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StorageInfoHeader(
            title: cfg.title,
            bytes: scan.bytes,
            count: scan.fileCount,
            note: cfg.caution,
          ),
          if (cfg.type == StorageCategoryType.snapshotDetail && _rootPath != null) ...[
            const SizedBox(height: AppGap.sm),
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
            AppEmpty(message: l10n.storageEmpty)
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
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
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
            const SizedBox(height: AppGap.xxs),
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
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = themeDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final cardBorder = storageCardBorder(context);
    return Column(
      children: [
        StorageTactileRow(
          onTap: onTap,
          builder: (_) => Container(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: cardBorder,
            ),
            child: Row(
              children: [
                Icon(Lucide.HardDrive, size: 18, color: cs.onSurface.withOpacity(0.7)),
                const SizedBox(width: AppGap.sm),
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
          padding: const EdgeInsets.all(AppGap.sm),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: cardBorder,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Lucide.BadgeInfo, size: 14, color: cs.onSurface.withOpacity(0.5)),
              ),
              const SizedBox(width: AppGap.xs),
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
