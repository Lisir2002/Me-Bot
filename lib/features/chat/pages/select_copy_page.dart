import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/chat_message.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';

/// 消息「选择复制」页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + SafeArea → AppPage(title/actions/body)
/// - padding all(16) → AppPagePadding.all
/// - ⚠️ body 自带 SingleChildScrollView，故 scrollable: false（否则嵌套滚动会 unbounded height）
class SelectCopyPage extends StatelessWidget {
  const SelectCopyPage({super.key, required this.message});
  final ChatMessage message;

  void _copyAll(BuildContext context) async {
    final l10n = context.l10n;
    // Ensure there is a text input connection on iOS before showing system copy UI
    // Here we bypass system menu by writing directly to clipboard and showing a snackbar
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.selectCopyPageCopiedAll,
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AppPage(
      title: l10n.selectCopyPageTitle,
      // body 自带滚动容器 → 必须 false，避免引擎再包一层 ListView 造成嵌套滚动
      scrollable: false,
      bodyPadding: AppPagePadding.all,
      actions: [
        TextButton.icon(
          onPressed: () => _copyAll(context),
          icon: Icon(Lucide.Copy, size: 18, color: cs.primary),
          label: Text(
            l10n.selectCopyPageCopyAll,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
      // 原外层 SafeArea 由 AppPage 的 safeArea(默认 true) 提供，故去掉
      body: Scrollbar(
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Text(
              message.content,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
