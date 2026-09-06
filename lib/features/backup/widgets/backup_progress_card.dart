import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';

/// 导出/导入进度卡片：✓ 图标 + 标题 + 线性进度 + 阶段 + 字节进度。
/// 在导出/导入期间内联展示；`progress < 0` 表示不确定进度（动画条）。
class BackupProgressCard extends StatelessWidget {
  const BackupProgressCard({
    super.key,
    required this.title,
    this.progress = -1,
    this.phase,
    this.processedBytes,
    this.totalBytes,
  });

  final String title;
  final double progress; // -1 表示不确定
  final String? phase;
  final int? processedBytes;
  final int? totalBytes;

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);

    final determinate = progress >= 0;
    final hasBytes = processedBytes != null && totalBytes != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.08), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Lucide.Check, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: determinate ? progress.clamp(0.0, 1.0) : null,
              minHeight: 6,
              backgroundColor: cs.outlineVariant.withOpacity(0.18),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  phase ?? '',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                ),
              ),
              if (determinate)
                Text(
                  '${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.85),
                  ),
                ),
            ],
          ),
          if (hasBytes) ...[
            const SizedBox(height: 4),
            Text(
              '${_fmtBytes(processedBytes!)} / ${_fmtBytes(totalBytes!)}',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 便捷：展示"正在导出"的进度卡（供导出/导入过程使用）。
class ExportingProgressCard extends StatelessWidget {
  const ExportingProgressCard({super.key, this.progress = -1});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: BackupProgressCard(
        title: l10n.backupPageExportToFile,
        progress: progress,
        phase: l10n.backupPhasePacking,
      ),
    );
  }
}