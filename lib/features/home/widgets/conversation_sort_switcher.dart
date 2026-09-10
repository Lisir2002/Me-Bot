import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/build_context_l10n.dart';

/// 对话排序切换器：自然 / 时间 / 助手分类
class ConversationSortSwitcher extends StatelessWidget {
  const ConversationSortSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMode = context.watch<SettingsProvider>().conversationSortMode;
    final l10n = context.l10n;

    Widget buildButton({
      required IconData icon,
      required ConversationSortMode mode,
      required String tooltip,
    }) {
      final selected = currentMode == mode;
      return Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? cs.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              icon,
              color: selected ? cs.primary : cs.onSurface.withOpacity(0.5),
            ),
            onPressed: () {
              context.read<SettingsProvider>().setConversationSortMode(mode);
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade200.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildButton(
            icon: Lucide.List,
            mode: ConversationSortMode.natural,
            tooltip: l10n.sideDrawerSortNatural,
          ),
          buildButton(
            icon: Lucide.Clock,
            mode: ConversationSortMode.time,
            tooltip: l10n.sideDrawerSortTime,
          ),
          buildButton(
            icon: Lucide.Users,
            mode: ConversationSortMode.byAssistant,
            tooltip: l10n.sideDrawerSortByAssistant,
          ),
        ],
      ),
    );
  }
}
