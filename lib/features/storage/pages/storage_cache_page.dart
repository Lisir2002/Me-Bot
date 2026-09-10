// no_raw_alert_dialog 白名单：现有弹窗待迁移到 AppDialog
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../core/services/logging/logger.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_directories.dart';
import '../widgets/storage_ios_widgets.dart';
import '../widgets/storage_info_header.dart';
import '../../../shared/widgets/snackbar.dart';

/// 可清理明细型（缓存）子页面。
/// 顶部两个描边按钮：清理头像缓存 / 清理缓存；下方明细卡。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/actions/body)
/// - padding LTRB(16,12,16,24) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl)
/// - 空态 → AppEmpty
/// - debugPrint → Logger.e（审计 P2-01）
/// - 两处逐字重复的清理确认弹窗 → 抽出 _confirmClear()
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

  /// 清理动作的统一二次确认。原实现里 _clearAvatar / _clearApp 各写了一份
  /// 逐字相同的 AlertDialog，抽出来避免文案/i18n 后续只改一处。
  Future<bool> _confirmClear() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storageCacheClearConfirmTitle),
        content: Text(l10n.storageCacheClearConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.storageCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.storageConfirmDeleteBtn,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _clearAvatar() async {
    try {
      if (!await _confirmClear() || !mounted) return;
      await _clearDirectories([(await AppDirectories.getAvatarCacheDirectory()).path]);
      await _refresh();
    } catch (e, s) {
      Logger.e('StorageCache', 'clear avatar cache failed', e, s);
      if (mounted) {
        showAppSnackBar(context,
            message: context.l10n.clearAvatarCacheFailed(e.toString()), type: NotificationType.error);
      }
    }
  }

  Future<void> _clearApp() async {
    try {
      if (!await _confirmClear() || !mounted) return;
      await _clearDirectories([(await AppDirectories.getCacheDirectory()).path]);
      await _refresh();
    } catch (e, s) {
      Logger.e('StorageCache', 'clear app cache failed', e, s);
      if (mounted) {
        showAppSnackBar(context,
            message: context.l10n.clearCacheFailed(e.toString()), type: NotificationType.error);
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
            note: l10n.storageCleanableNote,
            noteStyle: StorageInfoNoteStyle.cleanable,
          ),
          const SizedBox(height: AppGap.sm),
          Row(
            children: [
              Expanded(
                child: StorageOutlineButton(
                  icon: Lucide.ImageOff,
                  label: l10n.storageCacheClearAvatar,
                  onTap: _clearAvatar,
                ),
              ),
              const SizedBox(width: AppGap.sm),
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
            AppEmpty(message: l10n.storageEmpty)
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
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
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
          const SizedBox(width: AppGap.xs),
          Text(
            storageFormatBytes(entry.bytes),
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

/// 注：4 个 storage_* 子页原各有一份逐字重复的私有 _InfoHeader，
/// 现已统一提取为 ../widgets/storage_info_header.dart 的 StorageInfoHeader。
