// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';

import '../../../core/services/security/checkup_scanner.dart';
import '../../../core/services/security/key_health_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../theme/design_tokens.dart';

/// 安全评分等级。
enum SecurityScoreLevel {
  excellent(90, '优秀', AppStatusColor.success),
  good(70, '良好', Color(0xFF007AFF)),
  fair(50, '一般', AppStatusColor.warning),
  danger(0, '危险', AppStatusColor.danger);

  const SecurityScoreLevel(this.minScore, this.label, this.color);

  final int minScore;
  final String label;
  final Color color;

  static SecurityScoreLevel fromScore(int score) {
    for (final level in SecurityScoreLevel.values) {
      if (score >= level.minScore) return level;
    }
    return SecurityScoreLevel.danger;
  }
}

/// 安全评分计算结果（含扣分明细）。
class SecurityScoreResult {
  const SecurityScoreResult({
    required this.score,
    required this.dangerCount,
    required this.warnCount,
    required this.rotationCount,
    required this.lockEnabled,
    required this.allowlistEnabled,
  });

  final int score;
  final int dangerCount;
  final int warnCount;
  final int rotationCount;
  final bool lockEnabled;
  final bool allowlistEnabled;

  SecurityScoreLevel get level => SecurityScoreLevel.fromScore(score);

  /// 根据体检报告、密钥健康、门禁、白名单状态计算安全评分。
  ///
  /// 规则：基础 100 分，danger -20/项，warn -10/项，需轮换密钥 -15/个，
  /// 门禁开启 +10，白名单开启 +10，最终 clamp 到 0-100。
  factory SecurityScoreResult.compute({
    CheckupReport? report,
    List<KeyHealthInfo> health = const [],
    bool lockEnabled = false,
    bool allowlistEnabled = false,
  }) {
    var score = 100;
    final dangerCount = report?.dangerCount ?? 0;
    final warnCount = report?.warnCount ?? 0;
    final rotationCount = health.where((h) => h.needsRotation).length;

    score -= dangerCount * 20;
    score -= warnCount * 10;
    score -= rotationCount * 15;
    if (lockEnabled) score += 10;
    if (allowlistEnabled) score += 10;
    score = score.clamp(0, 100);

    return SecurityScoreResult(
      score: score,
      dangerCount: dangerCount,
      warnCount: warnCount,
      rotationCount: rotationCount,
      lockEnabled: lockEnabled,
      allowlistEnabled: allowlistEnabled,
    );
  }
}

/// 安全评分仪表盘（新功能 1）。
///
/// 页面顶部展示 0-100 分安全评分，用自定义进度环可视化。
/// 点击卡片展开评分明细（各项扣分明细）。
class SecurityScoreCard extends StatefulWidget {
  const SecurityScoreCard({
    super.key,
    required this.result,
    this.loading = false,
  });

  final SecurityScoreResult result;
  final bool loading;

  @override
  State<SecurityScoreCard> createState() => _SecurityScoreCardState();
}

class _SecurityScoreCardState extends State<SecurityScoreCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = widget.result;
    final level = r.level;

    return AppSectionCard(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppGap.md),
            child: Row(
              children: [
                _ScoreRing(score: r.score, color: level.color, loading: widget.loading),
                const SizedBox(width: AppGap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安全评分',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppGap.xxxs),
                      Text(
                        level.label,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: level.color,
                        ),
                      ),
                      const SizedBox(height: AppGap.xxxs),
                      Text(
                        _summaryText(l10n, r),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const AppSectionDivider(),
          _buildBreakdown(l10n, r),
        ],
      ],
    );
  }

  String _summaryText(AppLocalizations l10n, SecurityScoreResult r) {
    final parts = <String>[];
    if (r.dangerCount > 0) parts.add('${r.dangerCount} 高危');
    if (r.warnCount > 0) parts.add('${r.warnCount} 中危');
    if (r.rotationCount > 0) parts.add('${r.rotationCount} 密钥待轮换');
    if (parts.isEmpty) return '所有检查项均通过';
    return '${parts.join(' · ')} 待处理';
  }

  Widget _buildBreakdown(AppLocalizations l10n, SecurityScoreResult r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxs, AppGap.sm, AppGap.sm),
      child: Column(
        children: [
          _breakdownRow('高危发现', '${r.dangerCount} 项', '-${r.dangerCount * 20}',
              r.dangerCount > 0 ? AppStatusColor.danger : null),
          _breakdownRow('中危发现', '${r.warnCount} 项', '-${r.warnCount * 10}',
              r.warnCount > 0 ? AppStatusColor.warning : null),
          _breakdownRow('密钥待轮换', '${r.rotationCount} 个', '-${r.rotationCount * 15}',
              r.rotationCount > 0 ? AppStatusColor.warning : null),
          _breakdownRow('隐私门禁', r.lockEnabled ? '已开启' : '未开启',
              r.lockEnabled ? '+10' : '0',
              r.lockEnabled ? AppStatusColor.success : null),
          _breakdownRow('白名单策略', r.allowlistEnabled ? '已开启' : '未开启',
              r.allowlistEnabled ? '+10' : '0',
              r.allowlistEnabled ? AppStatusColor.success : null),
          const Divider(height: AppGap.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('总分',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('${r.score} / 100',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: r.level.color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, String delta, Color? color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppGap.xxxs),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
          const SizedBox(width: AppGap.md),
          SizedBox(
            width: 40,
            child: Text(
              delta,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ??
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义评分进度环。
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.color,
    this.loading = false,
  });

  final int score;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: loading ? null : score / 100,
              strokeWidth: 5,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (!loading)
            Text(
              '$score',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
