import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/security/app_lock_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import 'security_shared.dart';

/// 隐私门禁 section（安全中心第③段）。
///
/// 从 security_page.dart 拆出，职责：
/// - 门禁开关（双向生物验证）
/// - 解锁宽限期选择
/// - 立即锁定（P2 修复：lockNow 后通知父级刷新评分）
/// - 生物识别状态指示（新功能 3：实时显示验证状态 + 倒计时）
///
/// [lockFuture] 由父级在 initState 中创建并缓存，本 widget 用 FutureBuilder 消费。
/// [onLockChanged] 门禁状态变更后通知父级 setState（刷新安全评分）。
class SecurityAppLockSection extends StatefulWidget {
  const SecurityAppLockSection({
    super.key,
    required this.lockFuture,
    required this.onLockChanged,
  });

  /// 父级缓存的 Future（P1 #6），不在本 widget 内创建。
  final Future<AppLockService> lockFuture;

  /// 门禁开关 / 宽限期 / 立即锁定后通知父级刷新。
  final VoidCallback onLockChanged;

  @override
  State<SecurityAppLockSection> createState() => _SecurityAppLockSectionState();
}

class _SecurityAppLockSectionState extends State<SecurityAppLockSection> {
  /// 每秒刷新一次 build，让宽限期倒计时 / 状态指示实时更新。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<AppLockService>(
      future: widget.lockFuture,
      builder: (context, snap) {
        final lock = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SecuritySectionHeader(l10n.appLock, first: true),
            SecuritySectionDesc(l10n.appLockDesc),
            AppSectionCard(children: _lockRows(l10n, lock)),
          ],
        );
      },
    );
  }

  List<Widget> _lockRows(AppLocalizations l10n, AppLockService? lock) {
    if (lock == null) return const [];
    return [
      FutureBuilder<bool>(
        future: lock.canEnable(),
        builder: (context, snap) {
          final supported = snap.data ?? false;
          if (!supported) {
            return SecurityStatusRow(
              l10n.appLockUnsupported,
              icon: Lucide.Shield,
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 新功能 3：生物识别状态指示（仅门禁开启时显示）──
              if (lock.enabled) ...[
                _buildAuthStatusRow(lock),
                const AppSectionDivider(),
              ],
              AppSwitchRow(
                icon: Lucide.Shield,
                label: l10n.appLockEnable,
                value: lock.enabled,
                onChanged: (v) => _toggleLock(lock, v),
              ),
              if (lock.enabled) ...[
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.History,
                  label: l10n.appLockGrace,
                  detailText: _graceLabel(l10n, lock.graceMinutes),
                  onTap: () => _pickGrace(lock),
                ),
                if (lock.graceMinutes > 0) ...[
                  const AppSectionDivider(),
                  AppNavRow(
                    icon: Lucide.EyeOff,
                    label: l10n.appLockLockNow,
                    onTap: () => _lockNow(lock),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    ];
  }

  /// 新功能 3：当前验证状态行。
  ///
  /// - 已在宽限期内 → 绿点 + 「已验证 · X 分钟后需重新验证」
  /// - 未验证 / 宽限期已过 → 灰点 + 「未验证」
  /// - 宽限期为 0（每次都验证）→ 灰点 + 「未验证」
  ///
  /// 黄点「即将需要重新验证」需要精确剩余时间，而 `_lastUnlockAt` 为私有字段，
  /// 公共 API 仅暴露 [AppLockService.withinGrace] getter；当 getter 从 true 翻为
  /// false 时 UI 自动从绿变灰，过渡由 1s 定时器驱动。
  Widget _buildAuthStatusRow(AppLockService lock) {
    final cs = Theme.of(context).colorScheme;
    final inGrace = lock.graceMinutes > 0 && lock.withinGrace;

    final (Color dotColor, String label) = inGrace
        ? (AppStatusColor.success,
            '已验证 · ${lock.graceMinutes} 分钟后需重新验证')
        : (cs.onSurfaceVariant, '未验证');

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppGap.sm, vertical: AppGap.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: AppGap.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _graceLabel(AppLocalizations l10n, int minutes) => minutes == 0
      ? l10n.appLockGraceOff
      : l10n.appLockGraceMinutes(minutes);

  /// 开/关门禁都要求现场验证身份。
  Future<void> _toggleLock(AppLockService lock, bool v) async {
    final l10n = context.l10n;
    final ok = await lock.setEnabled(
      v,
      verify: () => lock.verifyWith(l10n.appLockVerifyToEnable),
    );
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(
        context,
        message: l10n.appLockAuthFailed,
        type: NotificationType.error,
      );
      return;
    }
    setState(() {});
    widget.onLockChanged();
  }

  Future<void> _pickGrace(AppLockService lock) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<int>(
      context: context,
      builder: AppSheet(
        title: l10n.appLockGrace,
        children: [
          for (final m in AppLockService.graceChoices)
            Builder(
              builder: (sheetCtx) => AppNavRow(
                icon: m == lock.graceMinutes ? Lucide.Check : Lucide.circleDot,
                label: _graceLabel(l10n, m),
                onTap: () => Navigator.pop(sheetCtx, m),
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await lock.setGraceMinutes(picked);
      if (mounted) {
        setState(() {});
        widget.onLockChanged();
      }
    }
  }

  /// P2 修复：立即锁定 → 清空解锁态 → 提示 → 通知父级刷新评分。
  Future<void> _lockNow(AppLockService lock) async {
    await lock.lockNow();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.appLockLockNow,
      type: NotificationType.info,
    );
    setState(() {});
    widget.onLockChanged();
  }
}
