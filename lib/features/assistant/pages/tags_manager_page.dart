import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/tag_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';

/// 标签管理页（助手维度）。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar → AppPage.selfScrolling(title/leading/actions/body)
/// - ⚠️ body 是 ReorderableListView（自带滚动）→ 必须 scrollable: false，
///   且 bodyPadding 置零（条目自带 LTRB(12,10,12,2) 内边距）
/// - 顶栏按钮复用共享 IosIconButton（符合 checklist 第 8 条）
/// - 魔法数字 → AppGap（无精确 token 的 10/14 保留字面量）
class TagsManagerPage extends StatefulWidget {
  const TagsManagerPage({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<TagsManagerPage> createState() => _TagsManagerPageState();
}

class _TagsManagerPageState extends State<TagsManagerPage> {
  Future<void> _createTag(BuildContext context) async {
    final l10n = context.l10n;
    final name = await AppDialog.input(
      context,
      title: l10n.assistantTagsCreateDialogTitle,
      hintText: l10n.assistantTagsNameHint,
      confirmText: l10n.assistantTagsCreateDialogOk,
      cancelText: l10n.assistantTagsCreateDialogCancel,
    );
    if (name == null || name.isEmpty) return;
    final tp = context.read<TagProvider>();
    if (tp.tags.any((t) => t.name == name)) return;
    await tp.createTag(name);
  }

  Future<void> _renameTag(BuildContext context, String tagId, String oldName) async {
    final l10n = context.l10n;
    final name = await AppDialog.input(
      context,
      title: l10n.assistantTagsRenameDialogTitle,
      initialText: oldName,
      hintText: l10n.assistantTagsNameHint,
      confirmText: l10n.assistantTagsRenameDialogOk,
      cancelText: l10n.assistantTagsCreateDialogCancel,
    );
    if (name == null || name.isEmpty) return;
    final tp = context.read<TagProvider>();
    if (tp.tags.any((t) => t.name == name && t.id != tagId)) return;
    await tp.renameTag(tagId, name);
  }

  Future<void> _deleteTag(BuildContext context, String tagId) async {
    final l10n = context.l10n;
    final ok = await AppDialog.confirm(
      context,
      title: l10n.assistantTagsDeleteConfirmTitle,
      message: l10n.assistantTagsDeleteConfirmContent,
      confirmText: l10n.assistantTagsDeleteConfirmOk,
      cancelText: l10n.assistantTagsDeleteConfirmCancel,
      danger: true,
    );
    if (ok) {
      await context.read<TagProvider>().deleteTag(tagId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tp = context.watch<TagProvider>();
    final tags = tp.tags;

    return AppPage.selfScrolling(
      title: l10n.assistantTagsManageTitle,
      // 保留 iOS 风格 ChevronLeft（AppPage 默认是 arrow_back_ios_new_rounded）
      leading: Padding(
        padding: const EdgeInsets.only(left: AppGap.xs),
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ChevronLeft,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppGap.xs),
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            minSize: 44,
            onTap: () => _createTag(context),
          ),
        ),
      ],
      // body 自带滚动容器 → 必须 false
      body: ReorderableListView.builder(
        itemCount: tags.length,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          // No shadow during drag; slight scale only
          return ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.02).animate(animation), child: child);
        },
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > oldIndex) newIndex -= 1;
          await context.read<TagProvider>().reorderTags(oldIndex, newIndex);
        },
        itemBuilder: (ctx, i) {
          final t = tags[i];
          return KeyedSubtree(
            key: ValueKey('tag-mobile-${t.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, 10, AppGap.sm, AppGap.xxxs),
              child: ReorderableDelayedDragStartListener(
                index: i,
                child: _MobileTagCard(
                  title: t.name,
                  onTap: () async {
                    await context
                        .read<TagProvider>()
                        .assignAssistantToTag(widget.assistantId, t.id);
                    if (mounted) Navigator.of(context).maybePop();
                  },
                  onRename: () => _renameTag(context, t.id, t.name),
                  onDelete: () => _deleteTag(context, t.id),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileTagCard extends StatelessWidget {
  const _MobileTagCard(
      {required this.title,
      required this.onTap,
      required this.onRename,
      required this.onDelete});
  final String title;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : const Color(0xFFF7F7F9);
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.12 : 0.10);

    Widget iconBtn(IconData icon, VoidCallback onPressed, {Color? color}) {
      return IosCardPress(
        baseColor: Colors.transparent,
        // 10 无精确 token，保留字面量
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        padding: const EdgeInsets.all(AppGap.xs),
        child: Icon(icon, size: 18, color: color ?? cs.onSurface),
      );
    }

    return IosCardPress(
      baseColor: bg,
      // 14 无精确 token，保留字面量
      borderRadius: BorderRadius.circular(14),
      pressedBlendStrength: 0.06,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            iconBtn(Lucide.Pencil, onRename),
            const SizedBox(width: AppGap.xxs),
            iconBtn(Lucide.Trash2, onDelete, color: cs.error),
          ],
        ),
      ),
    );
  }
}
