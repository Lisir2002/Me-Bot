import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/storage.dart';
import '../../../core/providers/storage_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/storage_categories.dart';
import '../widgets/storage_ios_widgets.dart';
import 'storage_cache_page.dart';
import 'storage_detail_page.dart';
import 'storage_log_page.dart';
import 'storage_media_page.dart';

/// 主"存储空间"页：环形图 + 可清理空间 + 8 分类列表。
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<StorageProvider>();
    if (!provider.initialized) {
      Future.microtask(() => provider.refresh());
    }
  }

  Future<void> _refresh() async =>
      context.read<StorageProvider>().refresh();

  Widget _subPage(StorageCategoryConfig config, StorageScan scan) {
    switch (config.type) {
      case StorageCategoryType.media:
        return StorageMediaPage(config: config, scan: scan);
      case StorageCategoryType.cleanableDetail:
        if (config.id == 'logs') {
          return StorageLogPage(config: config, scan: scan);
        }
        return StorageCachePage(config: config, scan: scan);
      case StorageCategoryType.readOnlyDetail:
      case StorageCategoryType.snapshotDetail:
        return StorageDetailPage(config: config, scan: scan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<StorageProvider>();
    final categories = buildStorageCategories(l10n);

    return Scaffold(
      appBar: AppBar(
        leading: StorageTactileIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.storagePageTitle),
        actions: [
          StorageTactileIconButton(
            icon: Lucide.RotateCw,
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
          if (provider.loading && !provider.hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (provider.error != null && !provider.hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  '${l10n.storageEmpty}\n${provider.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            )
          else
            _StorageBody(
              categories: categories,
              onOpen: (config) {
                final scan = provider.scanFor(config.id);
                if (scan == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _subPage(config, scan),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StorageBody extends StatefulWidget {
  const _StorageBody({required this.categories, required this.onOpen});
  final List<StorageCategoryConfig> categories;
  final void Function(StorageCategoryConfig config) onOpen;

  @override
  State<_StorageBody> createState() => _StorageBodyState();
}

class _StorageBodyState extends State<_StorageBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<StorageProvider>();
    final stats = provider.stats;
    if (stats == null) return const SizedBox.shrink();
    final cats = widget.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _progress,
          builder: (context, _) => _UsageCard(
            totalBytes: stats.totalBytes,
            cleanableBytes: stats.cleanableBytes,
            progress: _progress.value,
            categories: cats,
          ),
        ),
        const SizedBox(height: 12),
        StorageSectionHeader(l10n.storageCategoriesHeader, first: true),
        const SizedBox(height: 6),
        StorageSectionCard(
          children: [
            for (var i = 0; i < cats.length; i++) ...[
              if (i > 0) const StorageDivider(),
              StorageNavRow(
                icon: cats[i].icon,
                label: cats[i].title,
                onTap: () => widget.onOpen(cats[i]),
                detailBuilder: (ctx) {
                  final scan = provider.scanFor(cats[i].id);
                  if (scan == null) return const Text('-');
                  return Text(
                    '${storageFormatBytes(scan.bytes)} · ${l10n.storageItemsCount(scan.fileCount)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 已用空间卡片：标题 + 大数值 + 环形图 + 可清理空间。
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.totalBytes,
    required this.cleanableBytes,
    required this.progress,
    required this.categories,
  });
  final int totalBytes;
  final int cleanableBytes;
  final double progress;
  final List<StorageCategoryConfig> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final cardBg = theme.brightness == Brightness.dark
        ? Colors.white10
        : Colors.white.withOpacity(0.96);
    final provider = context.watch<StorageProvider>();

    // 环形图分段。
    final sections = <PieChartSectionData>[];
    var acc = 0.0;
    for (final c in categories) {
      final bytes = provider.scanFor(c.id)?.bytes ?? 0;
      if (bytes <= 0) continue;
      final seg = bytes / (totalBytes <= 0 ? 1 : totalBytes);
      sections.add(PieChartSectionData(
        value: seg * progress,
        color: c.color,
        radius: 12,
        showTitle: false,
      ));
      acc += seg;
    }
    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
        value: 1,
        color: cs.outlineVariant.withOpacity(0.2),
        radius: 12,
        showTitle: false,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: storageCardBorder(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageUsed,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 118,
                height: 118,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 42,
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          storageFormatBytes(totalBytes),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(acc * 100).clamp(0.0, 100.0).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _legend(context, provider)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 0.6, color: cs.outlineVariant.withOpacity(0.18)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.storageCleanable, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                storageFormatBytes(cleanableBytes),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, StorageProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final cats = categories.length <= 5 ? categories : categories.sublist(0, 5);
    final rows = <Widget>[];
    for (final c in cats) {
      final bytes = provider.scanFor(c.id)?.bytes ?? 0;
      if (bytes <= 0) continue;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
              ),
            ),
            Text(
              storageFormatBytes(bytes),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ));
    }
    if (rows.isEmpty) {
      rows.add(Text(
        '—',
        style: TextStyle(color: cs.onSurface.withOpacity(0.4)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}