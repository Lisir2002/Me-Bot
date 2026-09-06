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
///
/// 关键设计：每个 StatefulShellBranch 有独立 navigatorKey，避免 branch 间
/// 互相干扰。ChatPage 作为顶层 route（parentNavigatorKey = root），push 时
/// 覆盖整个 shell（包括底栏），不被底栏骨架包裹。
class AppRouter {
  AppRouter._();

  static late final GoRouter router;

  /// 在 MaterialApp.router 之前调用一次。
  static void init({required GlobalKey<NavigatorState> rootNavigatorKey}) {
    // 每个 branch 独立的 Navigator key —— 避免共享导致的状态混乱
    final branch0Key = GlobalKey<NavigatorState>(debugLabel: 'branch0-conversations');
    final branch1Key = GlobalKey<NavigatorState>(debugLabel: 'branch1-terminal');
    final branch2Key = GlobalKey<NavigatorState>(debugLabel: 'branch2-settings');

    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/conversations',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return _MobileScaffoldShell(navigationShell: navigationShell);
          },
          branches: [
            // [0] 对话列表 Tab
            StatefulShellBranch(
              navigatorKey: branch0Key,
              routes: [
                GoRoute(
                  path: '/conversations',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: ConversationListPage(),
                  ),
                ),
              ],
            ),
            // [1] 终端 Tab（占位）
            StatefulShellBranch(
              navigatorKey: branch1Key,
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
              navigatorKey: branch2Key,
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
        // ChatPage 作为独立顶层 route —— parentNavigatorKey 指向根 Navigator，
        // push 时会覆盖整个 StatefulShellRoute（包括底栏），不在 tab 骨架内。
        GoRoute(
          path: '/chat/:id',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return CustomTransitionPage<void>(
              key: ValueKey<String>(id),
              child: ChatPage(conversationId: id),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = Offset(1.0, 0.0);
                const end = Offset.zero;
                const curve = Curves.easeOutCubic;
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ── Shell 壳（NavigationBar 骨架，只包三个 tab 根页面）──

class _MobileScaffoldShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _MobileScaffoldShell({required this.navigationShell});

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
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        elevation: 0,
        backgroundColor: cs.surface,
        destinations: [
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
            icon: const Icon(Icons.settings_outlined_rounded),
            selectedIcon: Icon(Icons.settings, color: cs.primary),
            label: l10n.settingsPageTitle,
          ),
        ],
      ),
    );
  }
}
