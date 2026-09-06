import 'package:flutter/material.dart';

/// 终端页面（占位，后续要用到）。
/// 真实骨架：标题 + 图标 + 简短说明 + 版本号。
class TerminalPlaceholderPage extends StatelessWidget {
  const TerminalPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.terminal,
                  size: 36,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Terminal',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Coming soon — CLI for AI agent commands',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v0.0.27',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
