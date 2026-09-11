import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/backup.dart';
import '../../../core/services/backup/data_sync.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/logging/logger.dart';
import '../../../core/services/logging/log_tags.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_directories.dart';
import '../widgets/storage_ios_widgets.dart';

/// 单个本地副本条目。
class SnapshotInfo {
  final String name;
  final String path;
  final int bytes;
  final DateTime modified;
  final bool pinned;

  const SnapshotInfo({
    required this.name,
    required this.path,
    required this.bytes,
    required this.modified,
    required this.pinned,
  });
}

/// 本地副本管理页：设置卡 + 副本列表 + 立即备份 + 恢复/导出/删除/保留。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title / leading / actions / body)
/// - padding LTRB(16,12,16,24) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl)
/// - 三态走手动分支（本页是「本地可变状态 + 多次异步刷新」，
///   不是「整页一个 Future」，不适合 AppPageStates）
/// - 私有 _ActionChip 的按压 + 触觉逻辑收敛到 IosTactileRow
class LocalSnapshotPage extends StatefulWidget {
  const LocalSnapshotPage({super.key});

  @override
  State<LocalSnapshotPage> createState() => _LocalSnapshotPageState();
}

class _LocalSnapshotPageState extends State<LocalSnapshotPage> {
  List<SnapshotInfo> _snapshots = const [];
  // 首帧即为加载态：_load() 里要先 await SharedPreferences 才会置 _loading，
  // 初值给 false 会闪一帧空态再变加载，视觉上是一次多余的闪烁。
  bool _loading = true;
  bool _busy = false;

  // 设置状态
  bool _keepLocal = true;
  int _keepCount = 3;
  bool _keepLastWeek = true;
  bool _keepLastMonth = true;
  bool _notifyDone = true;
  // 备份频率：0=手动 1=每天 2=每周 3=自动（默认自动，与原写死显示一致）。
  // 注：当前应用无后台调度器，此值记录用户意图偏好，非自动执行。
  int _freq = 3;
  // 占用上限（GB）：0=不限制。旧实现误把“保留份数”当 GB 显示，此处改为真实档位。
  int _sizeLimitGb = 0;

  DataSync get _sync => DataSync(chatService: context.read<ChatService>());

  @override
  void initState() {
    super.initState();
    Logger.d(LogTags.storage, 'page init: local snapshot page');
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _keepLocal = prefs.getBool('backup_keep_local') ?? true;
      _keepCount = prefs.getInt('backup_keep_count') ?? 3;
      _keepLastWeek = prefs.getBool('backup_keep_last_week') ?? true;
      _keepLastMonth = prefs.getBool('backup_keep_last_month') ?? true;
      _notifyDone = prefs.getBool('backup_notify_done') ?? true;
      _freq = prefs.getInt('backup_freq') ?? 3;
      _sizeLimitGb = prefs.getInt('backup_size_limit_gb') ?? 0;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final dir = await _snapDir();
    final list = <SnapshotInfo>[];
    if (await dir.exists()) {
      final pinned = (await SharedPreferences.getInstance())
          .getStringList('backup_pinned_snapshots') ?? const <String>[];
      await for (final ent in dir.list(followLinks: false)) {
        if (ent is! File) continue;
        if (!ent.path.toLowerCase().endsWith('.zip')) continue;
        try {
          final stat = ent.statSync();
          list.add(SnapshotInfo(
            name: ent.path.split('/').last,
            path: ent.path,
            bytes: stat.size,
            modified: stat.modified,
            pinned: pinned.contains(ent.path),
          ));
        } catch (_) {}
      }
    }
    list.sort((a, b) => b.modified.compareTo(a.modified));
    if (!mounted) return;
    setState(() {
      _snapshots = list;
      _loading = false;
    });
  }

  Future<Directory> _snapDir() async {
    final root = await AppDirectories.getAppDataDirectory();
    return Directory('${root.path}/snapshots');
  }

  Future<void> _setBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
    if (mounted) setState(() {});
  }

  Future<void> _backupNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    Logger.i(LogTags.storage, 'backup: creating local snapshot');
    try {
      final dir = await _snapDir();
      await dir.create(recursive: true);
      final zip = await _sync.prepareBackupFile(const WebDavConfig());
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '');
      final dest = File('${dir.path}/minime-core_backup_$stamp.zip');
      await zip.copy(dest.path);

      // 按保留份数清理最旧副本
      await _enforceRetention(dir);
      if (_notifyDone && mounted) {
        showAppSnackBar(context, message: '${l10nOf().snapshotBackupNow} ✓',
            type: NotificationType.success);
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enforceRetention(Directory dir) async {
    final zips = <File>[];
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is File && ent.path.toLowerCase().endsWith('.zip')) zips.add(ent);
    }
    // 1) 按保留份数清理最旧副本
    zips.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    while (zips.length > _keepCount) {
      final oldest = zips.removeAt(0);
      try {
        await oldest.delete();
      } catch (_) {}
    }
    // 2) 按占用上限清理（固定副本永不被删）
    if (_sizeLimitGb > 0) {
      final pinned = (await SharedPreferences.getInstance())
          .getStringList('backup_pinned_snapshots') ?? const <String>[];
      final limitBytes = _sizeLimitGb * 1024 * 1024 * 1024;
      var total = zips.fold<int>(0, (s, f) => s + f.statSync().size);
      final trimmable = zips.where((f) => !pinned.contains(f.path)).toList()
        ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in trimmable) {
        if (total <= limitBytes) break;
        try {
          final sz = f.statSync().size;
          await f.delete();
          total -= sz;
        } catch (_) {}
      }
    }
  }

  AppLocalizations l10nOf() => context.l10n;

  Future<RestoreMode?> _chooseMode() {
    final l10n = l10nOf();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.backupPageSelectImportMode,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeCard(
              color: cardColor,
              icon: Lucide.RotateCw,
              title: l10n.backupPageOverwriteMode,
              subtitle: l10n.backupPageOverwriteModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.overwrite),
            ),
            const SizedBox(height: 10),
            _ModeCard(
              color: cardColor,
              icon: Lucide.GitFork,
              title: l10n.backupPageMergeMode,
              subtitle: l10n.backupPageMergeModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.merge),
            ),
          ],
        ),
        actions: [
          AppDialog.button(
            label: l10n.backupPageCancel,
            kind: AppDialogButtonKind.secondary,
            filled: false,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(SnapshotInfo snap) async {
    final l10n = l10nOf();
    final mode = await _chooseMode();
    if (mode == null || !mounted) return;
    setState(() => _busy = true);
    Logger.i(LogTags.storage, 'restore: from snapshot ${snap.name} (mode: $mode)');
    try {
      await _sync.restoreFromLocalFile(File(snap.path), const WebDavConfig(), mode: mode);
      if (mounted) {
        await AppDialog.alert(
          context,
          title: l10n.backupPageRestartRequired,
          message: l10n.backupPageRestartContent,
          buttonText: l10n.backupPageOK,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(SnapshotInfo snap) async {
    final rect = _shareOrigin();
    Logger.i(LogTags.storage, 'export: sharing snapshot ${snap.name}');
    try {
      await Share.shareXFiles([XFile(snap.path)], sharePositionOrigin: rect);
    } catch (_) {}
  }

  Rect _shareOrigin() {
    final overlay = Overlay.of(context);
    final ro = overlay.context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      final c = ro.size.center(Offset.zero);
      final g = ro.localToGlobal(c);
      return Rect.fromCenter(center: g, width: 1, height: 1);
    }
    final size = MediaQuery.of(context).size;
    return Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
  }

  Future<void> _delete(SnapshotInfo snap) async {
    final ok = await _confirmDelete(snap);
    if (ok != true || !mounted) return;
    Logger.i(LogTags.storage, 'delete: removing snapshot ${snap.name}');
    try {
      final f = File(snap.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _refresh();
  }

  Future<bool?> _confirmDelete(SnapshotInfo snap) {
    final l10n = l10nOf();
    return AppDialog.confirm(
      context,
      title: l10n.snapshotDelete,
      message: '${l10n.snapshotSafetyNote}\n\n${snap.name}',
      confirmText: l10n.backupPageOK,
      cancelText: l10n.storageCancel,
      danger: true,
    );
  }

  Future<void> _togglePin(SnapshotInfo snap) async {
    final prefs = await SharedPreferences.getInstance();
    var pinned = prefs.getStringList('backup_pinned_snapshots') ?? <String>[];
    if (pinned.contains(snap.path)) {
      pinned.remove(snap.path);
    } else {
      pinned.add(snap.path);
    }
    await prefs.setStringList('backup_pinned_snapshots', pinned);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf();
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    // 与 storage 分组卡一致的底色，直接复用 storage 的工具函数避免重复定义。
    final cardBg = storageCardBackground(Theme.of(context));
    final totalBytes = _snapshots.fold<int>(0, (s, e) => s + e.bytes);

    return AppPage(
      title: l10n.snapshotTitle,
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
      // crossAxisAlignment.stretch 必需：AppPage 的滚动容器给子项是紧宽度，
      // 但 Column 默认 center 会把宽度放宽，卡片会缩成内容宽度。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 设置卡
          AppSectionHeader(l10n.snapshotSettingsHeader, first: true),
          const SizedBox(height: 6),
          StorageSectionCard(
            children: [
              StorageSwitchRow(
                icon: Lucide.Save,
                label: l10n.snapshotKeepLocal,
                value: _keepLocal,
                onChanged: (v) async {
                  setState(() => _keepLocal = v);
                  await _setBool('backup_keep_local', v);
                },
              ),
              const StorageDivider(),
              StorageNavRow(
                icon: Lucide.CalendarClock,
                label: l10n.snapshotFrequency,
                detailText: _freqLabel(l10n),
                onTap: () => _pickFrequency(l10n),
              ),
              const StorageDivider(),
              StorageNavRow(
                icon: Lucide.Copy,
                label: l10n.snapshotKeepCount,
                detailText: l10n.snapshotCopies(_keepCount),
                onTap: () => _pickKeepCount(l10n),
              ),
              const StorageDivider(),
              StorageSwitchRow(
                icon: Lucide.CalendarDays,
                label: l10n.snapshotKeepLastWeek,
                value: _keepLastWeek,
                onChanged: (v) async {
                  setState(() => _keepLastWeek = v);
                  await _setBool('backup_keep_last_week', v);
                },
              ),
              const StorageDivider(),
              StorageSwitchRow(
                icon: Lucide.CalendarRange,
                label: l10n.snapshotKeepLastMonth,
                value: _keepLastMonth,
                onChanged: (v) async {
                  setState(() => _keepLastMonth = v);
                  await _setBool('backup_keep_last_month', v);
                },
              ),
              const StorageDivider(),
              StorageNavRow(
                icon: Lucide.HardDriveDownload,
                label: l10n.snapshotSizeLimit,
                detailText: _sizeLimitLabel(l10n),
                onTap: () => _pickSizeLimit(l10n),
              ),
              const StorageDivider(),
              StorageSwitchRow(
                icon: Lucide.Bell,
                label: l10n.snapshotNotifyDone,
                value: _notifyDone,
                onChanged: (v) async {
                  setState(() => _notifyDone = v);
                  await _setBool('backup_notify_done', v);
                },
              ),
            ],
          ),

          const SizedBox(height: AppGap.sm),
          Container(
            padding: const EdgeInsets.all(AppGap.sm),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(themeDark ? 0.08 : 0.06),
                width: 0.6,
              ),
            ),
            child: Text(
              l10n.snapshotSafetyNote,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          StorageTactileRow(
            onTap: _busy ? null : _backupNow,
            builder: (_) => StorageOutlineButton(
              icon: Lucide.Plus,
              label: l10n.snapshotBackupNow,
              onTap: _busy ? () {} : _backupNow,
            ),
          ),

          const SizedBox(height: AppGap.sm),
          AppSectionHeader(l10n.snapshotListHeader(_snapshots.length, storageFormatBytes(totalBytes))),
          const SizedBox(height: 6),

          if (_loading)
            AppLoading(verticalPadding: AppGap.xxl)
          else if (_snapshots.isEmpty)
            AppEmpty(message: l10n.storageEmpty)
          else
            StorageSectionCard(
              children: [
                for (var i = 0; i < _snapshots.length; i++) ...[
                  if (i > 0) const StorageDivider(),
                  _SnapshotTile(
                    snap: _snapshots[i],
                    onRestore: () => _restore(_snapshots[i]),
                    onExport: () => _export(_snapshots[i]),
                    onDelete: () => _delete(_snapshots[i]),
                    onPin: () => _togglePin(_snapshots[i]),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pickKeepCount(AppLocalizations l10n) async {
    final opts = [1, 3, 5, 10, 20];
    final prefs = await SharedPreferences.getInstance();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.snapshotKeepCount,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in opts)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(n),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('${l10n.snapshotCopies(n)}${n == _keepCount ? ' ✓' : ''}'),
                ),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _keepCount = v);
    await prefs.setInt('backup_keep_count', v);
    await _enforceRetention(await _snapDir());
  }

  String _freqLabel(AppLocalizations l10n) {
    switch (_freq) {
      case 0:
        return l10n.snapshotFreqManual;
      case 1:
        return l10n.snapshotFreqDaily;
      case 2:
        return l10n.snapshotFreqWeekly;
      case 3:
        return l10n.snapshotFreqAuto;
      default:
        return l10n.snapshotFreqAuto;
    }
  }

  String _sizeLimitLabel(AppLocalizations l10n) {
    if (_sizeLimitGb <= 0) return l10n.snapshotSizeUnlimited;
    return '$_sizeLimitGb GB';
  }

  Future<void> _pickFrequency(AppLocalizations l10n) async {
    final tiers = <(int, String)>[
      (0, l10n.snapshotFreqManual),
      (1, l10n.snapshotFreqDaily),
      (2, l10n.snapshotFreqWeekly),
      (3, l10n.snapshotFreqAuto),
    ];
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.snapshotFrequency,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, label) in tiers)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('$label${id == _freq ? ' ✓' : ''}'),
                ),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _freq = v);
    await prefs.setInt('backup_freq', v);
  }

  Future<void> _pickSizeLimit(AppLocalizations l10n) async {
    final tiers = <(int, String)>[
      (0, l10n.snapshotSizeUnlimited),
      (1, '1 GB'),
      (2, '2 GB'),
      (5, '5 GB'),
      (10, '10 GB'),
    ];
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.snapshotSizeLimit,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (gb, label) in tiers)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(gb),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text('$label${gb == _sizeLimitGb ? ' ✓' : ''}'),
                ),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _sizeLimitGb = v);
    await prefs.setInt('backup_size_limit_gb', v);
    await _enforceRetention(await _snapDir());
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StorageTactileRow(
      onTap: onTap,
      builder: (_) => Container(
        padding: const EdgeInsets.all(AppGap.sm),
        decoration: BoxDecoration(
          color: color,
          // 14 无精确 token（md=12 / lg=16），保留字面量
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                // 10 无精确 token（sm=8 / md=12），保留字面量
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: AppGap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppGap.xxxs),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            Icon(Lucide.ChevronRight, size: 18, color: cs.onSurface),
          ],
        ),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.snap,
    required this.onRestore,
    required this.onExport,
    required this.onDelete,
    required this.onPin,
  });
  final SnapshotInfo snap;
  final VoidCallback onRestore;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final time = snap.name.contains('backup_')
        ? _fmtTime(snap.modified)
        : snap.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Lucide.Database, size: 22, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Lucide.Cpu, size: 12, color: cs.onSurface.withOpacity(0.5)),
                        const SizedBox(width: AppGap.xxs),
                        Expanded(
                          child: Text(
                            '${l10n.snapshotAutoBadge} · ${storageFormatBytes(snap.bytes)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (snap.pinned) ...[
                Icon(Lucide.MapPin, size: 16, color: cs.primary),
                const SizedBox(width: AppGap.xxs),
              ],
            ],
          ),
          const SizedBox(height: AppGap.xs),
          Row(
            children: [
              _ActionChip(
                icon: Lucide.RotateCw,
                label: l10n.snapshotRestore,
                onTap: onRestore,
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Lucide.Export,
                label: l10n.snapshotExport,
                onTap: onExport,
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Lucide.MapPin,
                label: snap.pinned ? l10n.snapshotKeep : l10n.snapshotPin,
                onTap: onPin,
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Lucide.Trash2,
                label: l10n.snapshotDelete,
                danger: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 副本条目上的小操作胶囊（恢复 / 导出 / 固定 / 删除）。
///
/// 按压效果（缩放 0.95 + 抬起后延迟 80ms 复位）与触觉反馈统一交给
/// [IosTactileRow]，本组件只负责外观，去掉了原来手写的
/// GestureDetector + AnimatedScale + Haptics 三件套。
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final bg = themeDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return IosTactileRow(
      onTap: onTap,
      pressedScale: 0.95,
      releaseDelay: const Duration(milliseconds: 80),
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          // 9 无精确 token（sm=8 / md=12），保留字面量
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: AppGap.xxs),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
