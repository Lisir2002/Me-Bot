import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

/// 移动端共享底栏 —— 三个 tab 根页面各自 Scaffold 的 bottomNavigationBar。
///
/// 路由跳转用 GoRouter 的 go()，会自动匹配 StatefulShellRoute 的
/// StatefulShellBranch，保持每个 tab 的独立 Navigator 栈状态。
class MobileBottomNav extends StatelessWidget {
  final int currentIndex;
  const MobileBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        selectedIcon: Icon(Icons.chat_bubble_rounded, color: cs.primary),
        label: l10n.mobileTabConversations,
      ),
      NavigationDestination(
        icon: const Icon(Icons.code_rounded),
        selectedIcon: Icon(Icons.code, color: cs.primary),
        label: l10n.mobileTabTerminal,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings_rounded, color: cs.primary),
        label: l10n.settingsPageTitle,
      ),
    ];

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) {
        if (index == currentIndex) return;
        const paths = ['/conversations', '/terminal', '/settings'];
        context.go(paths[index]);
      },
      elevation: 0,
      backgroundColor: cs.surface,
      destinations: destinations,
    );
  }
}
