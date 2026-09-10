import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/design_tokens.dart';

/// 安全中心各 section 共享的轻量组件与工具函数。
///
/// 从 security_page.dart 961 行单文件中抽出，避免 5 个 section 各自复制粘贴。
/// 所有组件严格走设计系统：AppSectionCard / AppStatusColor / Lucide 图标。

/// 卡内统一状态行（原 _banner 的设计系统版）。
class SecurityStatusRow extends StatelessWidget {
  const SecurityStatusRow(
    this.text, {
    super.key,
    this.icon,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = color ?? cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Container(
        padding: const EdgeInsets.all(AppGap.sm),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: tint, size: 18),
              const SizedBox(width: AppGap.sm),
            ],
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip 横向包裹容器（统一内边距与间距）。
class SecurityChipWrap extends StatelessWidget {
  const SecurityChipWrap(this.chips, {super.key});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppGap.sm, AppGap.xxs, AppGap.sm, AppGap.xxs),
        child: Wrap(spacing: 6, runSpacing: -6, children: chips),
      );
}

/// 格式化日期为 YYYY-MM-DD，null 时返回「从未」。
String fmtDate(AppLocalizations l10n, DateTime? d) {
  if (d == null) return l10n.never;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 格式化时间为 MM-DD HH:mm。
String fmtTime(DateTime t) =>
    '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
