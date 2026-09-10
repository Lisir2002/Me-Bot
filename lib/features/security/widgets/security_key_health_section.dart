import 'package:flutter/material.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/security/key_health_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import 'security_shared.dart';

/// 密钥健康 section（PR-7 可视化重构）。
///
/// 从 security_page.dart 单文件抽出。职责：
/// - loading 时显示转圈；空列表显示「无密钥」状态行；
/// - **P1 修复**：行 label 显示 provider 的展示名（[ProviderConfig.name]），
///   空名时回退到 providerId，不再直接把 providerId 当名字；
/// - **新功能 4：密钥轮换倒计时**——每行 detail 中按 90 天阈值推导：
///   从未轮换（红）/ 已超期 X 天（红）/ X 天后需轮换（黄，<7 天）/ X 天后轮换（正常）；
/// - needsRotation 时仍保留 suggestRotation 标签 + RotateCw 标记已轮换按钮；
/// - 任意一行需要轮换时，卡片下方显示 goRotate 引导文案。
class SecurityKeyHealthSection extends StatelessWidget {
  const SecurityKeyHealthSection({
    super.key,
    required this.health,
    required this.loading,
    required this.settings,
    required this.onMarkRotated,
    required this.onGotoProvider,
  });

  /// 各 provider 的密钥健康快照。
  final List<KeyHealthInfo> health;

  /// 健康数据是否正在加载。
  final bool loading;

  /// 用于把 providerId 解析成用户可读的展示名。
  final SettingsProvider settings;

  /// 点击 RotateCw：标记当前 provider 已轮换。
  final Future<void> Function(KeyHealthInfo info) onMarkRotated;

  /// 点击行：跳转到 provider 详情页换 Key。
  final Future<void> Function(KeyHealthInfo info) onGotoProvider;

  /// 轮换阈值（与 KeyHealthService 默认值一致：90 天）。
  static const int _thresholdDays = 90;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final anyRotation = health.any((h) => h.needsRotation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecuritySectionHeader(l10n.keyHealth),
        SecuritySectionDesc(l10n.keyHealthDesc),
        AppSectionCard(children: _healthRows(context, l10n)),
        if (anyRotation)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppGap.sm, AppGap.xxs, AppGap.sm, 0),
            child: Text(
              l10n.goRotate,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _healthRows(BuildContext context, AppLocalizations l10n) {
    if (loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppGap.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (health.isEmpty) {
      return [
        SecurityStatusRow(l10n.keyHealthEmpty, icon: Lucide.KeyRound),
      ];
    }
    return [
      for (var i = 0; i < health.length; i++) ...[
        if (i > 0) const AppSectionDivider(),
        _healthRow(context, l10n, health[i]),
      ],
    ];
  }

  Widget _healthRow(BuildContext context, AppLocalizations l10n, KeyHealthInfo h) {
    // P1：用 provider 展示名，空名回退 providerId。
    final cfg = settings.providerConfigs[h.providerId];
    final displayName =
        (cfg != null && cfg.name.isNotEmpty) ? cfg.name : h.providerId;

    // 新功能 4：轮换倒计时文案 + 颜色。
    final countdown = _rotationCountdown(context, h);

    return AppNavRow(
      icon: Lucide.KeyRound,
      label: displayName,
      onTap: () => onGotoProvider(h),
      detailBuilder: (_) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${h.keyCount} · ${fmtDate(l10n, h.lastRotatedAt)}'),
          const SizedBox(width: AppGap.xs),
          Text(
            countdown.text,
            style: TextStyle(
              fontSize: 13,
              color: countdown.color,
            ),
          ),
          const SizedBox(width: AppGap.xs),
          Text(
            h.needsRotation ? l10n.suggestRotation : l10n.rotationOk,
            style: h.needsRotation
                ? const TextStyle(color: AppStatusColor.warning)
                : null,
          ),
          // needsRotation 时显示「标记已轮换」按钮
          if (h.needsRotation)
            Tooltip(
              message: l10n.rotateAction,
              child: IosIconButton(
                haptics: true,
                icon: Lucide.RotateCw,
                size: 14,
                minSize: 28,
                onTap: () => onMarkRotated(h),
              ),
            ),
        ],
      ),
    );
  }

  /// 推导轮换倒计时文案与颜色。
  ///
  /// 规则：
  /// - 从未轮换 → 「从未轮换」（红）；
  /// - 已超期 → 「已超期 X 天」（红），daysOverdue 为 null 时降级为「从未轮换」；
  /// - 未超期且距到期 <7 天 → 「X 天后需轮换」（黄）；
  /// - 未超期且 >=7 天 → 「X 天后轮换」（正常文字色）。
  _Countdown _rotationCountdown(BuildContext context, KeyHealthInfo h) {
    final cs = Theme.of(context).colorScheme;
    final normalColor = cs.onSurface.withValues(alpha: 0.6);

    // 从未轮换过。
    if (h.lastRotatedAt == null) {
      return const _Countdown('从未轮换', AppStatusColor.danger);
    }

    // 已超期：红色 + 已超期天数。
    if (h.isOverdue(_thresholdDays)) {
      final overdue = h.daysOverdue(_thresholdDays);
      if (overdue == null) {
        return const _Countdown('从未轮换', AppStatusColor.danger);
      }
      return _Countdown('已超期 $overdue 天', AppStatusColor.danger);
    }

    // 未超期：daysUntilRotation 必为非空正数（lastRotatedAt 非 null）。
    final daysLeft = h.daysUntilRotation(_thresholdDays);
    if (daysLeft == null) {
      return _Countdown('从未轮换', normalColor);
    }
    if (daysLeft < 7) {
      return _Countdown('$daysLeft 天后需轮换', AppStatusColor.warning);
    }
    return _Countdown('$daysLeft 天后轮换', normalColor);
  }
}

/// 轮换倒计时展示值：文案 + 颜色。
class _Countdown {
  const _Countdown(this.text, this.color);

  final String text;
  final Color color;
}
