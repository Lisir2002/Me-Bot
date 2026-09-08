import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/design_tokens.dart';
import 'storage_ios_widgets.dart';

/// storage_* 子页共用的顶部信息头：分类名 + 占用大小 + 文件数 + 说明角标。
///
/// 原先 4 个子页（log / cache / detail / media）各持有一份逐字重复的
/// 私有 `_InfoHeader`，唯一差异是底部角标：
/// - [StorageInfoNoteStyle.caution]   琥珀色 —— 有风险提示的分类（本地数据/模型等）
/// - [StorageInfoNoteStyle.cleanable] 绿色   —— 可安全清理的分类（日志/缓存）
///
/// 用法：
/// ```dart
/// StorageInfoHeader(
///   title: cfg.title,
///   bytes: scan.bytes,
///   count: scan.fileCount,
///   note: l10n.storageCleanableNote,
///   noteStyle: StorageInfoNoteStyle.cleanable,
/// )
/// ```
class StorageInfoHeader extends StatelessWidget {
  const StorageInfoHeader({
    super.key,
    required this.title,
    required this.bytes,
    required this.count,
    required this.note,
    this.noteStyle = StorageInfoNoteStyle.caution,
  });

  final String title;
  final int bytes;
  final int count;
  final String note;
  final StorageInfoNoteStyle noteStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final caution = noteStyle == StorageInfoNoteStyle.caution;
    return Container(
      padding: const EdgeInsets.all(AppGap.sm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: storageCardBorder(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: AppGap.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                storageFormatBytes(bytes),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: AppGap.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: AppGap.xxs),
                child: Text(
                  l10n.storageItemsCount(count),
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppGap.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: AppGap.xxs),
            decoration: BoxDecoration(
              color: (caution ? Colors.amber : Colors.green).withOpacity(0.12),
              // 6 无精确 token，保留字面量
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              note,
              style: TextStyle(
                  fontSize: 11, color: caution ? Colors.orange : Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}

/// 角标风格：风险提示（琥珀） / 可清理（绿）。
enum StorageInfoNoteStyle { caution, cleanable }
