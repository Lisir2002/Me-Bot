import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../core/services/logging/logger.dart';
import '../../../core/services/logging/log_tags.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/storage_ios_widgets.dart';
import '../widgets/storage_info_header.dart';
import 'log_viewer_page.dart';
import '../../../shared/widgets/snackbar.dart';

/// 可清理明细型（日志）子页面。
/// 顶部：查看日志 / 清理日志；下方日志明细卡（无独立按钮）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/actions/body)
/// - padding LTRB(16,12,16,24) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl)
/// - 空态 → AppEmpty
/// - debugPrint → Logger.e（顺带对齐 P0 日志升级，审计 P2-01）
class StorageLogPage extends StatefulWidget {
  const StorageLogPage({super.key, required this.config});
  final StorageCategoryConfig config;

  @override
  State<StorageLogPage> createState() => _StorageLogPageState();
}

class _StorageLogPageState extends State<StorageLogPage> {
  @override
  void initState() {
    super.initState();
    Logger.d(LogTags.storage, 'page init: log detail page');
  }

  Future<void> _refresh() async =>
      Provider.of<StorageProvider>(context, listen: false).refresh();

  /// 从实时 Provider 状态取当前分类快照，仅以此作为数据源。
  /// 这是唯一的数据来源，避免持有构造函数传入的冻结快照导致清理后不刷新。
  StorageScan get _scan =>
      context.read<StorageProvider>().scanFor(widget.config.id) ??
      const StorageScan(id: 'none', bytes: 0, fileCount: 0, entries: []);

  Future<void> _clearLogs() async {
    try {
      final l10n = context.l10n;
      final ok = await AppDialog.confirm(
        context,
        title: l10n.storageLogClearConfirmTitle,
        message: l10n.storageLogClearConfirmBody,
        confirmText: l10n.storageConfirmDeleteBtn,
        cancelText: l10n.storageCancel,
        danger: true,
      );
      if (ok != true || !mounted) return;
      for (final e in _scan.entries) {
        try {
          final f = File(e.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      Logger.i(LogTags.storage, 'delete: log files cleared (${_scan.entries.length} entries)');
      await _refresh();
    } catch (e, s) {
      Logger.e('StorageLog', 'clear logs failed', e, s);
      if (mounted) {
        showAppSnackBar(context,
            message: context.l10n.clearLogsFailed(e.toString()), type: NotificationType.error);
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
                  icon: Lucide.ScrollText,
                  label: l10n.storageLogView,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppGap.sm),
              Expanded(
                child: StorageFilledButton(
                  icon: Lucide.Trash2,
                  label: l10n.storageLogClear,
                  bg: const Color(0xFFFF5F5F),
                  onTap: _clearLogs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppSectionHeader(l10n.storageDetailHeader, first: true),
          const SizedBox(height: 6),
          if (scan.entries.isEmpty)
            AppEmpty(message: l10n.storageEmpty)
          else
            StorageSectionCard(
              children: [
                for (var i = 0; i < scan.entries.length; i++) ...[
                  if (i > 0) const StorageDivider(),
                  _LogRow(entry: scan.entries[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final StorageEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
      child: Row(
        children: [
          Icon(Lucide.FileText, size: 16, color: cs.onSurface.withOpacity(0.6)),
          const SizedBox(width: 10),
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
