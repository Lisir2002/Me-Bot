import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/storage/log_store.dart';
import '../../../core/services/logging/logger.dart';
import '../../../core/services/logging/log_tags.dart';
import '../../../core/services/logging/log_exporter.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_list_view.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../widgets/log_settings_sheet.dart';
import '../widgets/storage_ios_widgets.dart';

/// 日志查看页：顶栏含设置齿轮；Tab 上下文/请求日志/应用日志。
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  // 默认落到「请求/网络」Tab，用户与模型对话的日志就在这里，避免打开即空态。
  int _tab = 1;
  LogEntry? _selected;
  List<LogEntry> _entries = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Logger.d(LogTags.storage, 'page init: log viewer');
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    switch (_tab) {
      case 0: _entries = await LogStore.sessions(); break;
      case 1: _entries = await LogStore.requests(); break;
      default: _entries = await LogStore.application(); break;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _selectTab(int i) async {
    if (i == _tab) return;
    setState(() { _tab = i; _selected = null; });
    await _load();
  }

  /// 导出全部日志文件为 zip 并调系统分享（P3-32）。
  Future<void> _exportLogs() async {
    try {
      final path = await LogExporter.exportLogs();
      if (!mounted) return;
      // iPad/大屏需要分享锚点；这里用屏幕中心兜底
      final size = MediaQuery.of(context).size;
      await Share.shareXFiles(
        [XFile(path)],
        sharePositionOrigin: Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 1,
          height: 1,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // ignore: hardcoded_ui_string
      showAppSnackBar(context, message: '导出失败: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tabs = [l10n.storageLogContext, l10n.storageLogNetwork, l10n.storageLogRuntime];

    // 页面壳走设计系统 AppPage（返回键/标题/actions 统一）；
    // pill 分段条是页内组件，放 body 首行（与原 AppBar.bottom 视觉等价）。
    return AppPage.selfScrolling(
      title: l10n.storageCateLogs,
      actions: [
        Tooltip(
          // ignore: hardcoded_ui_string
          message: '导出日志',
          child: IosIconButton(
            icon: Lucide.Share,
            size: 20,
            minSize: 44,
            // ignore: hardcoded_ui_string
            semanticLabel: '导出日志',
            onTap: _exportLogs,
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: l10n.logSettingsTitle,
          child: IosIconButton(
            icon: Lucide.Settings,
            size: 20,
            minSize: 44,
            semanticLabel: l10n.logSettingsTitle,
            onTap: () {
              showAppSheet<void>(
                context: context,
                builder: const LogSettingsSheet(),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _TabChip(
                      label: tabs[i],
                      active: _tab == i,
                      onTap: () => _selectTab(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _selected != null
                    ? LogEntryDetail(entry: _selected!)
                    : _buildList(l10n, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, ColorScheme cs) {
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          l10n.storageLogEmpty,
          style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
        ),
      );
    }
    return AppListViewBuilder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TactileLogCard(
              title: e.title,
              time: e.time,
              onTap: () => setState(() => _selected = e),
            ),
            if (i < _entries.length - 1) const SizedBox(height: 8),
          ],
        );
      },
      topPadding: 8,
      bottomPadding: 24,
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
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
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: Text(
            widget.label,
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

class _TactileLogCard extends StatelessWidget {
  const _TactileLogCard({required this.title, required this.time, required this.onTap});
  final String title;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final bg = themeDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return StorageTactileRow(
      onTap: onTap,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: storageCardBorder(context),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${l10n.storageLogCurrent} - $time',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
            ),
            const SizedBox(width: 4),
            Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class LogEntryDetail extends StatelessWidget {
  const LogEntryDetail({super.key, required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppListView(
      topPadding: 8,
      bottomPadding: 24,
      children: [
        Text(
          entry.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          entry.time,
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            entry.body,
            style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}