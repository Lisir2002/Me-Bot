import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/design_tokens.dart';

/// 安全中心各 section 共享的轻量组件与工具函数。
///
/// 从 security_page.dart 961 行单文件中抽出，避免 5 个 section 各自复制粘贴。
/// 所有组件严格走设计系统：AppSectionCard / AppStatusColor / Lucide 图标。

/// 分组小节标题（13px w600，与 backup_page 的 header 范式一致）。
class SecuritySectionHeader extends StatelessWidget {
  const SecuritySectionHeader(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            AppGap.sm, first ? 0 : AppGap.lg, AppGap.sm, AppGap.xxs),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      );
}

/// 分组小节描述（12px 弱化）。
class SecuritySectionDesc extends StatelessWidget {
  const SecuritySectionDesc(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.sm),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
}

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

/// 卡内「标题 + 右侧操作」行头（与 AppNavRow 的横向留白对齐）。
class SecurityRowHeader extends StatelessWidget {
  const SecurityRowHeader(this.text, {super.key, required this.trailing});

  final String text;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppGap.sm, vertical: AppGap.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
            trailing,
          ],
        ),
      );
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
