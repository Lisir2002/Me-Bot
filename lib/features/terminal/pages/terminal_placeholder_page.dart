import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../theme/design_tokens.dart';

/// 终端页面（占位，后续要用到）。
/// 真实骨架：标题 + 图标 + 简短说明 + 版本号。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar(transparent/elevation 0) → AppPage 顶栏已是同款配置
/// - body 用 Center 做垂直居中 → ⚠️ 必须 scrollable: false，
///   否则 ListView 内的 Center 拿不到有界高度、无法垂直居中
/// - 魔法数字间距/圆角 → AppGap / AppRadius
class TerminalPlaceholderPage extends StatelessWidget {
  const TerminalPlaceholderPage({super.key});

  /// 版本号来源：仅在首次挂载时解析一次（避免每次 build 重复调用平台通道）。
  static final Future<PackageInfo> _versionFuture = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return AppPage(
      title: l10n.mobileTabTerminal,
      scrollable: false,
      bodyPadding: AppPagePadding.zero,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                Icons.terminal,
                size: 36,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: AppGap.xl),
            Text(
              l10n.mobileTabTerminal,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppGap.xs),
            Text(
              l10n.terminalComingSoon,
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: AppGap.xxl),
            FutureBuilder<PackageInfo>(
              future: _versionFuture,
              builder: (context, snap) {
                final v = snap.hasData ? 'v${snap.data!.version}' : '';
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    v,
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
