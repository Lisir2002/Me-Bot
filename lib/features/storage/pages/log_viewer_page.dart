import 'package:flutter/material.dart';

import '../../../core/services/storage/log_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/log_settings_sheet.dart';
import '../widgets/storage_ios_widgets.dart';

/// 日志查看页：顶栏含设置齿轮；Tab 上下文/请求日志/应用日志。
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  int _tab = 0;
  LogEntry? _selected;
  List<LogEntry> _entries = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tabs = [l10n.storageLogContext, l10n.storageLogNetwork, l10n.storageLogRuntime];

    return Scaffold(
      appBar: AppBar(
        leading: StorageTactileIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.storageCateLogs),
        actions: [
          StorageTactileIconButton(
            icon: Lucide.Settings,
            color: cs.onSurface,
            size: 20,
            semanticLabel: l10n.logSettingsTitle,
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: cs.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => const LogSettingsSheet(),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = _entries[i];
        return _TactileLogCard(
          title: e.title,
          time: e.time,
          onTap: () => setState(() => _selected = e),
        );
      },
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
    final l10n = AppLocalizations.of(context)!;
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
          border: Border.all(color: cs.outlineVariant.withOpacity(themeDark ? 0.08 : 0.06), width: 0.6),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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