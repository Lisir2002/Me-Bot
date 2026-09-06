import 'package:flutter/material.dart';

import '../../../core/models/storage.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/palettes.dart';

/// 8 个存储分类的 UI 配置，在 build 时生成以取得本地化标题。
List<StorageCategoryConfig> buildStorageCategories(AppLocalizations l10n) {
  const t = ThemePalettes.defaultPalette;
  final primary = t.light.primary;
  return [
    StorageCategoryConfig(
      id: 'images',
      title: l10n.storageCatePic,
      icon: Lucide.Image,
      color: primary,
      type: StorageCategoryType.media,
      caution: l10n.storageCautionRisk,
      supportSourceFilter: true,
      supportOrderFilter: true,
      supportDelete: true,
    ),
    StorageCategoryConfig(
      id: 'upload',
      title: l10n.storageCateFile,
      icon: Lucide.FileText,
      color: const Color(0xFF2E9E5B),
      type: StorageCategoryType.media,
      caution: l10n.storageCautionRisk,
      supportSourceFilter: true,
      supportOrderFilter: true,
      supportDelete: true,
    ),
    StorageCategoryConfig(
      id: 'chats',
      title: l10n.storageCateChats,
      icon: Lucide.Database,
      color: const Color(0xFF8E5CC9),
      type: StorageCategoryType.readOnlyDetail,
      caution: l10n.storageCautionRisk,
    ),
    StorageCategoryConfig(
      id: 'snapshots',
      title: l10n.storageCateSnapshots,
      icon: Lucide.Copy,
      color: const Color(0xFF00A8B5),
      type: StorageCategoryType.snapshotDetail,
      caution: l10n.storageCautionRisk,
    ),
    StorageCategoryConfig(
      id: 'avatars',
      title: l10n.storageCateAvatars,
      icon: Lucide.Boxes,
      color: const Color(0xFFF08C2E),
      type: StorageCategoryType.readOnlyDetail,
      caution: l10n.storageCautionRisk,
    ),
    StorageCategoryConfig(
      id: 'cache',
      title: l10n.storageCateCache,
      icon: Lucide.Zap,
      color: const Color(0xFFE5C210),
      type: StorageCategoryType.cleanableDetail,
      caution: l10n.storageCautionSafe,
    ),
    StorageCategoryConfig(
      id: 'logs',
      title: l10n.storageCateLogs,
      icon: Lucide.Eraser,
      color: const Color(0xFF8E9096),
      type: StorageCategoryType.cleanableDetail,
      caution: l10n.storageCautionSafe,
    ),
    StorageCategoryConfig(
      id: 'other',
      title: l10n.storageCateOther,
      icon: Lucide.Box,
      color: const Color(0xFFE05C7B),
      type: StorageCategoryType.readOnlyDetail,
      caution: l10n.storageCautionOther,
    ),
  ];
}