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
/// StatefulShellRoute 只负责多 tab 独立 Navigator 栈 + 保持状态，
/// 不包任何 Scaffold 骨架 —— 每个 tab 根页面自己决定要不要底栏。
/// ChatPage 作为 /conversations 的嵌套 route，push 上去覆盖底栏。
class AppRouter {
  AppRouter._();

  static late final GoRouter router;

  static void init({required GlobalKey<NavigatorState> rootNavigatorKey}) {
    final branch0Key = GlobalKey<NavigatorState>(debugLabel: 'branch0-conversations');
    final branch1Key = GlobalKey<NavigatorState>(debugLabel: 'branch1-terminal');
    final branch2Key = GlobalKey<NavigatorState>(debugLabel: 'branch2-settings');

    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/conversations',
      routes: [
        StatefulShellRoute.indexedStack(
          // Shell 本身只是 IndexedStack —— 没有 Scaffold、没有底栏、没有 Drawer
          builder: (context, state, navigationShell) => navigationShell,
          branches: [
            // [0] 对话列表 Tab + ChatPage（push 覆盖底栏）
            StatefulShellBranch(
              navigatorKey: branch0Key,
              routes: [
                GoRoute(
                  path: '/conversations',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: ConversationListPage(),
                  ),
                  routes: [
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
            // [1] 终端 Tab
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
      ],
    );
  }
}
