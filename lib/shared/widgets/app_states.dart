import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

// ──────────────────────────────────────────────────────────────
// 三态占位组件：AppLoading / AppError / AppEmpty
//
// AppPage 的 states 机制内置了 loading/error/empty/data 决策，
// 这里的三个组件负责三态的『视觉』。页面也可以单独引用它们
// （例如 provider 驱动的三态），保证加载/错误/空态观感全局统一。
// ──────────────────────────────────────────────────────────────

/// 加载占位 —— 居中转圈 + 可选文案
class AppLoading extends StatelessWidget {
  final String? message;
  final double verticalPadding;
  const AppLoading({super.key, this.message, this.verticalPadding = 60});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (message != null) ...[
              const SizedBox(height: AppGap.sm),
              Text(
                message!,
                style: AppText.muted(Theme.of(context).textTheme, cs),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误占位 —— 居中图标 + 错误信息 + 重试按钮
class AppError extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final double verticalPadding;
  const AppError({
    super.key,
    this.message,
    this.onRetry,
    this.verticalPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 36, color: cs.error.withOpacity(0.7)),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppGap.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppGap.xl),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppText.muted(tt, cs),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppGap.md),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空态占位 —— 居中图标 + 文案 + 可选动作
class AppEmpty extends StatelessWidget {
  final String message;
  final String? hint;
  final IconData icon;
  final Widget? action;
  final double verticalPadding;
  const AppEmpty({
    super.key,
    required this.message,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.verticalPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: AppGap.md),
            Text(message, textAlign: TextAlign.center, style: AppText.h3(tt).copyWith(color: cs.onSurface.withOpacity(0.8))),
            if (hint != null) ...[
              const SizedBox(height: AppGap.xs),
              Text(hint!, textAlign: TextAlign.center, style: AppText.hint(tt, cs)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppGap.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}