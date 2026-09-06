import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/backup.dart';
import '../../../core/services/backup/data_sync.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
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
class LocalSnapshotPage extends StatefulWidget {
  const LocalSnapshotPage({super.key});

  @override
  State<LocalSnapshotPage> createState() => _LocalSnapshotPageState();
}

class _LocalSnapshotPageState extends State<LocalSnapshotPage> {
  List<SnapshotInfo> _snapshots = const [];
  bool _loading = false;
  bool _busy = false;

  // 设置状态
  bool _keepLocal = true;
  int _keepCount = 3;
  bool _keepLastWeek = true;
  bool _keepLastMonth = true;
  bool _notifyDone = true;

  DataSync get _sync => DataSync(chatService: context.read<ChatService>());

  @override
  void initState() {
    super.initState();
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
    zips.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    while (zips.length > _keepCount) {
      final oldest = zips.removeAt(0);
      try {
        await oldest.delete();
      } catch (_) {}
    }
  }

  AppLocalizations l10nOf() => AppLocalizations.of(context)!;

  Future<RestoreMode?> _chooseMode() {
    final l10n = l10nOf();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupPageSelectImportMode),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.backupPageCancel),
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
    try {
      await _sync.restoreFromLocalFile(File(snap.path), const WebDavConfig(), mode: mode);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(l10n.backupPageRestartRequired),
            content: Text(l10n.backupPageRestartContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(),
                child: Text(l10n.backupPageOK),
              ),
            ],
          ),
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
    try {
      final f = File(snap.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _refresh();
  }

  Future<bool?> _confirmDelete(SnapshotInfo snap) {
    final l10n = l10nOf();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.snapshotDelete),
        content: Text('${l10n.snapshotSafetyNote}\n\n${snap.name}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.storageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.backupPageOK, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
    final cardBg = themeDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    final totalBytes = _snapshots.fold<int>(0, (s, e) => s + e.bytes);

    return Scaffold(
      appBar: AppBar(
        leading: StorageTactileIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.snapshotTitle),
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
          // 设置卡
          StorageSectionHeader(l10n.snapshotSettingsHeader, first: true),
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
                detailText: l10n.snapshotFrequencyAuto,
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
                detailText: '$_keepCount GB',
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

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 12),
          StorageTactileRow(
            onTap: _busy ? null : _backupNow,
            builder: (_) => StorageOutlineButton(
              icon: Lucide.Plus,
              label: l10n.snapshotBackupNow,
              onTap: _busy ? () {} : _backupNow,
            ),
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              l10n.snapshotListHeader(_snapshots.length, storageFormatBytes(totalBytes)),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 6),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_snapshots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  l10n.storageEmpty,
                  style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            )
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
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.snapshotKeepCount),
        children: [
          for (final n in opts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(n),
              child: Text('${l10n.snapshotCopies(n)}${n == _keepCount ? ' ✓' : ''}'),
            ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _keepCount = v);
    await prefs.setInt('backup_keep_count', v);
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
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
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
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
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final time = snap.name.contains('backup_')
        ? _fmtTime(snap.modified)
        : snap.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                        const SizedBox(width: 4),
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
                const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 8),
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

class _ActionChip extends StatefulWidget {
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
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.danger ? cs.error : cs.primary;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final bg = themeDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _pressed = false);
      }),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: (widget.danger ? cs.error : cs.primary).withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}