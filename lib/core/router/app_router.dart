import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/user_provider.dart';
import '../../theme/design_tokens.dart';
import 'package:minime_core/l10n/app_localizations.dart';
import '../../features/conversation/pages/chat_page.dart';
import '../../features/conversation/pages/conversation_list_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/terminal/pages/terminal_placeholder_page.dart';

/// 全局路由配置（仅移动端使用 Desktop 继续用 MaterialApp.home）。
///
/// 使用 StatefulShellRoute.indexedStack 实现多 tab 独立 Navigator 栈，
/// tab 切换后状态天然保留（IndexedStack 不 dispose 子节点）。
/// 现有 387 处 Navigator.push/pop 全部不动 —— go_router 和原生 Navigator 共存。
class AppRouter {
  AppRouter._();

  static late final GoRouter router;

  /// 在 MaterialApp.router 之前调用一次。
  static void init({required GlobalKey<NavigatorState> rootNavigatorKey}) {
    final shellNavigatorKey = GlobalKey<NavigatorState>();

    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/conversations',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return _MobileScaffoldShell(
              navigationShell: navigationShell,
              shellNavigatorKey: shellNavigatorKey,
            );
          },
          branches: [
            // [0] 对话列表 Tab
            StatefulShellBranch(
              navigatorKey: shellNavigatorKey,
              routes: [
                GoRoute(
                  path: '/conversations',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: ConversationListPage(),
                  ),
                  routes: [
                    // 点某条对话 → push ChatPage（同一 tab 内）
                    GoRoute(
                      path: 'chat/:id',
                      pageBuilder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return MaterialPage(
                          key: ValueKey<String>(id),
                          child: ChatPage(conversationId: id),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            // [1] 终端 Tab（占位）
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/terminal',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: TerminalPlaceholderPage(),
                  ),
                ),
              ],
            ),
            // [2] 设置 Tab
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: SettingsPage(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shell 壳（NavigationBar + Drawer 骨架）──

class _MobileScaffoldShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final GlobalKey<NavigatorState> shellNavigatorKey;

  const _MobileScaffoldShell({
    required this.navigationShell,
    required this.shellNavigatorKey,
  });

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
    Widget build(BuildContext context) {
      final cs = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context)!;

      return Scaffold(
        drawer: const _DrawerSkeleton(),
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onTap,
          elevation: 0,
          backgroundColor: cs.surface,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.chat_outlined),
              selectedIcon: Icon(Icons.chat, color: cs.primary),
              label: l10n.mobileTabConversations,
            ),
            NavigationDestination(
              icon: const Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal, color: cs.primary),
              label: l10n.mobileTabTerminal,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: cs.primary),
              label: l10n.settingsPageTitle,
            ),
          ],
        ),
      );
    }
}

// ── Drawer 导航骨架（占位，等后续填）──

class _DrawerSkeleton extends StatelessWidget {
  const _DrawerSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final userName = context.watch<UserProvider>().name;
    final displayName = userName.isNotEmpty ? userName : l10n.mobileDrawerGuest;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: cs.primary.withOpacity(0.15),
                    child: Text(
                      displayName.characters.first,
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'MiniMe-Core',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Placeholder list — 等后续填
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      l10n.mobileDrawerComingSoon,
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    enabled: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
