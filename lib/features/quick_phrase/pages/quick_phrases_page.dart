import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../theme/design_tokens.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/ios_tactile.dart';

/// 快捷短语列表页（全局 / 助手专属）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + (Center 空态 | ReorderableListView) → AppPage(title/leading/actions/body)
/// - `scrollable: false` + `bodyPadding: zero`：ReorderableListView 自带滚动与 padding(16)，
///   空态的 `Center` 也需要有界高度才能垂直居中（引擎 scrollable 给的是无界高度）
/// - 空态 → `AppEmpty(message:, icon: Lucide.Zap)`
/// - **私有 `_TactileIconButton` → 共享 `IosIconButton`**（删除私有副本）
/// - **外层 `showModalBottomSheet` → `showAppSheet`**（统一圆角 / SafeArea / 键盘避让），
///   内层编辑表单**保持自建**——它属于 AppSheet 明示不适用的
///   「居中标题 + 左右操作按钮 + 多行输入」复杂弹层
///
/// 注：`_TactileIconButton` → 共享 `IosIconButton`；`_TactileCard` → 共享 `IosTactileRow`
/// + `IosPressColor`（ios_tactile.dart 新增原语）。仍保留私有：
/// `_IosOutlineButton` / `_IosFilledButton`（项目暂无共享按钮组件）。
/// 行为变更：卡片点按触觉从「无条件 Haptics.soft()」改为受 设置→列表项触觉 开关约束。
class QuickPhrasesPage extends StatefulWidget {
  const QuickPhrasesPage({super.key, this.assistantId});

  final String? assistantId; // null = 全局短语，非 null = 助手专属

  @override
  State<QuickPhrasesPage> createState() => _QuickPhrasesPageState();
}

class _QuickPhrasesPageState extends State<QuickPhrasesPage> {
  @override
  void initState() {
    super.initState();
    // Provider 自行负责加载
  }

  Future<void> _showAddEditSheet({QuickPhrase? phrase}) async {
    final result = await showAppSheet<Map<String, String>?>(
      context: context,
      builder: _QuickPhraseEditSheet(
        phrase: phrase,
        assistantId: widget.assistantId,
      ),
    );

    if (result != null) {
      final title = result['title']?.trim() ?? '';
      final content = result['content']?.trim() ?? '';

      if (title.isEmpty || content.isEmpty) return;

      if (phrase == null) {
        // 新增
        final newPhrase = QuickPhrase(
          id: const Uuid().v4(),
          title: title,
          content: content,
          isGlobal: widget.assistantId == null,
          assistantId: widget.assistantId,
        );
        await context.read<QuickPhraseProvider>().add(newPhrase);
      } else {
        // 更新
        await context.read<QuickPhraseProvider>().update(
          phrase.copyWith(title: title, content: content),
        );
      }
    }
  }

  Future<void> _deletePhrase(QuickPhrase phrase) async {
    await context.read<QuickPhraseProvider>().delete(phrase.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final phrases = widget.assistantId == null
        ? quickPhraseProvider.globalPhrases
        : quickPhraseProvider.getForAssistant(widget.assistantId!);

    return AppPage(
      title: widget.assistantId == null
          ? l10n.quickPhraseGlobalTitle
          : l10n.quickPhraseAssistantTitle,
      leading: Tooltip(
        message: l10n.quickPhraseBackTooltip,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.quickPhraseBackTooltip,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Tooltip(
          message: l10n.quickPhraseAddTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.quickPhraseAddTooltip,
            onTap: () => _showAddEditSheet(),
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      scrollable: false,
      bodyPadding: AppPagePadding.zero,
      body: phrases.isEmpty
          // AppEmpty 的图标固定 40（原实现 64），文案也走全局 h3 样式。
          // 若要完全还原原观感，把这里换回自定义 Center+Column 即可。
          ? AppEmpty(
              message: l10n.quickPhraseEmptyMessage,
              icon: Lucide.Zap,
              verticalPadding: 0,
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(AppGap.md),
              itemCount: phrases.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                // 平滑缩放，不带阴影/抬升
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final t = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: 0.98 + 0.02 * t,
                      child: child,
                    );
                  },
                );
              },
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                // 立即更新，保证落下动画顺滑
                context.read<QuickPhraseProvider>().reorderPhrases(
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                      assistantId: widget.assistantId,
                    );
              },
              itemBuilder: (context, index) {
                final phrase = phrases[index];
                return KeyedSubtree(
                  key: ValueKey('reorder-quick-phrase-${phrase.id}'),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppGap.sm),
                      child: Slidable(
                        key: ValueKey(phrase.id),
                        endActionPane: ActionPane(
                          motion: const StretchMotion(),
                          extentRatio: 0.35,
                          children: [
                            CustomSlidableAction(
                              autoClose: true,
                              backgroundColor: Colors.transparent,
                              child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? cs.error.withOpacity(0.22)
                                      : cs.error.withOpacity(0.14),
                                  // 14 无精确 token（AppRadius.md=12 / lg=16），保留字面量
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: cs.error.withOpacity(0.35),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppGap.sm,
                                  vertical: AppGap.xs,
                                ),
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Lucide.Trash2,
                                        color: cs.error,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        l10n.quickPhraseDeleteButton,
                                        style: TextStyle(
                                          color: cs.error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              onPressed: (_) => _deletePhrase(phrase),
                            ),
                          ],
                        ),
                        child: IosTactileRow(
                          pressedScale: 0.98,
                          releaseDelay: const Duration(milliseconds: 120),
                          onTap: () => _showAddEditSheet(phrase: phrase),
                          builder: (ctx, pressed) {
                            final overlay = pressed
                                ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
                                : Colors.transparent;
                            final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
                            return Container(
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(overlay, baseBg),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: cs.outlineVariant.withOpacity(isDark ? 0.1 : 0.08),
                                    width: 0.6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Lucide.Zap, size: 18, color: cs.primary),
                                              const SizedBox(width: AppGap.xs),
                                              Expanded(
                                                child: Text(
                                                  phrase.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 15, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: AppGap.xs),
                                          Text(
                                            phrase.content,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: cs.onSurface.withOpacity(0.7)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AppGap.xs),
                                    Icon(Lucide.ChevronRight,
                                        size: 16, color: cs.onSurface.withOpacity(0.5)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 新增/编辑快捷短语的弹层内容。
///
/// 属于 AppSheet 明示不适用的复杂弹层（居中标题 + 左右操作按钮 + 多行输入），
/// 因此内容自建；但外层调用统一走 `showAppSheet`，
/// 由它负责 SafeArea(top:false) + 顶部圆角 + 键盘避让，
/// 所以这里**不再重复** `SafeArea` 与 `MediaQuery.viewInsets`。
class _QuickPhraseEditSheet extends StatefulWidget {
  const _QuickPhraseEditSheet({
    required this.phrase,
    required this.assistantId,
  });

  final QuickPhrase? phrase;
  final String? assistantId;

  @override
  State<_QuickPhraseEditSheet> createState() => _QuickPhraseEditSheetState();
}

class _QuickPhraseEditSheetState extends State<_QuickPhraseEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.phrase?.title ?? '');
    _contentController = TextEditingController(
      text: widget.phrase?.content ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(
        left: AppGap.md,
        right: AppGap.md,
        top: AppGap.sm,
        bottom: AppGap.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppRadius.circular),
              ),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          Center(
            child: Text(
              widget.phrase == null ? l10n.quickPhraseAddTitle : l10n.quickPhraseEditTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: AppGap.md),
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.quickPhraseTitleLabel,
              filled: true,
              fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
              ),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          TextField(
            controller: _contentController,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: l10n.quickPhraseContentLabel,
              alignLabelWithHint: true,
              filled: true,
              fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
              ),
            ),
          ),
          const SizedBox(height: AppGap.md),
          Row(
            children: [
              Expanded(
                child: _IosOutlineButton(
                  label: l10n.quickPhraseCancelButton,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppGap.sm),
              Expanded(
                child: _IosFilledButton(
                  label: l10n.quickPhraseSaveButton,
                  onTap: () {
                    Navigator.of(context).pop({
                      'title': _titleController.text,
                      'content': _contentController.text,
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- iOS 触觉反馈辅助组件（无涟漪）---
// 注：_TactileIconButton → 共享 IosIconButton；
//     _TactileCard → 共享 IosTactileRow（均见 shared/widgets/ios_tactile.dart）。

class _IosOutlineButton extends StatefulWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_IosOutlineButton> createState() => _IosOutlineButtonState();
}

class _IosOutlineButtonState extends State<_IosOutlineButton> {
  bool _pressed = false;
  void _set(bool v) { if (_pressed != v) setState(() => _pressed = v); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () { Haptics.soft(); widget.onTap(); },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppGap.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.primary.withOpacity(0.5)),
          ),
          child: Text(widget.label,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _IosFilledButton extends StatefulWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_IosFilledButton> createState() => _IosFilledButtonState();
}

class _IosFilledButtonState extends State<_IosFilledButton> {
  bool _pressed = false;
  void _set(bool v) { if (_pressed != v) setState(() => _pressed = v); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () { Haptics.soft(); widget.onTap(); },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppGap.sm),
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Text(widget.label,
              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
