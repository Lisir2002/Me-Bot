import 'dart:io' show File;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'assistant_settings_edit_page.dart';

/// 助手管理页：可拖拽排序的助手列表 + 新增 / 删除。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ReorderableListView → AppPage(title / leading / actions / body)
/// - **`scrollable: false`**：`ReorderableListView` 自带滚动，再套引擎的 ListView 会嵌套滚动冲突（checklist 3c）
/// - padding LTRB(12,12,12,100) → fromLTRB(AppGap.sm, AppGap.sm, AppGap.sm, 100)
/// - 新增助手弹层：手写 `showModalBottomSheet` → `showAppSheet`（保留居中标题，故内容自建）
/// - 私有 `_TactileIconButton` → `IosIconButton(haptics: true)`；
///   `_TactileCard` → `IosCardPress`；`_IosOutline/FilledButton` → `IosTactileRow`
class AssistantSettingsPage extends StatelessWidget {
  const AssistantSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final assistants = context.watch<AssistantProvider>().assistants;

    return AppPage(
      title: l10n.assistantSettingsPageTitle,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Tooltip(
          message: l10n.assistantSettingsAddSheetSave,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            onTap: () async {
              final name = await _showAddAssistantSheet(context);
              if (name == null) return;
              final id = await context
                  .read<AssistantProvider>()
                  .addAssistant(name: name.trim(), context: context);
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AssistantSettingsEditPage(assistantId: id)),
              );
            },
          ),
        ),
        const SizedBox(width: AppGap.xs),
      ],
      // ReorderableListView 自带滚动 → 引擎不再包 ListView
      scrollable: false,
      // 100 无对应 token（列表底部为拖拽留白），保留字面量
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.sm, AppGap.sm, 100),
      body: ReorderableListView.builder(
        itemCount: assistants.length,
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > oldIndex) newIndex -= 1;
          // Immediately update UI for smooth experience
          final assistantProvider = context.read<AssistantProvider>();
          await assistantProvider.reorderAssistants(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOutBack.transform(animation.value);
              return Transform.scale(
                scale: 0.98 + 0.02 * t,
                child: Material(
                  elevation: 0, // remove drag shadow
                  shadowColor: Colors.transparent,
                  color: Colors.transparent,
                  // 14 无精确 token（md=12 / lg=16），保留字面量
                  borderRadius: BorderRadius.circular(14),
                  child: child,
                ),
              );
            },
          );
        },
        itemBuilder: (context, index) {
          final item = assistants[index];
          return KeyedSubtree(
            key: ValueKey('reorder-assistant-${item.id}'),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: Padding(
                // 10 无精确 token（xs=8 / sm=12），保留字面量
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssistantCard(item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.item});
  final Assistant item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseBg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    // 原 `_TactileCard` 的手写按压逻辑（overlay 叠加 + 0.98 缩放 + 卡触觉开关）
    // 与 `IosCardPress` 完全等价：Color.alphaBlend(c@a, bg) == Color.lerp(bg, c, a)。
    final content = IosCardPress(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AssistantSettingsEditPage(assistantId: item.id)),
        );
      },
      baseColor: baseBg,
      pressedBlendStrength: isDark ? 0.06 : 0.04,
      pressedScale: 0.98,
      duration: const Duration(milliseconds: 160),
      // 14 无精确 token，保留字面量
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          // 14 无精确 token，保留字面量
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withOpacity(isDark ? 0.12 : 0.08),
            width: 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppGap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AssistantAvatar(item: item, size: 44),
                  const SizedBox(width: AppGap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (!item.deletable)
                              _TagPill(text: l10n.assistantSettingsDefaultTag, color: cs.primary),
                          ],
                        ),
                        const SizedBox(height: AppGap.xxs),
                        Text(
                          (item.systemPrompt.trim().isEmpty
                              ? l10n.assistantSettingsNoPromptPlaceholder
                              : item.systemPrompt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.7),
                              height: 1.25),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Slidable(
      key: ValueKey('slidable-assistant-${item.id}'),
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        extentRatio: 0.35,
        children: [
          CustomSlidableAction(
            autoClose: true,
            backgroundColor: Colors.transparent,
            onPressed: (_) async {
              final count = context.read<AssistantProvider>().assistants.length;
              if (count <= 1) {
                showAppSnackBar(
                  context,
                  message: l10n.assistantSettingsAtLeastOneAssistantRequired,
                  type: NotificationType.warning,
                );
                return;
              }
              final ok = await _confirmDelete(context, l10n);
              if (ok == true) {
                final success = await context.read<AssistantProvider>().deleteAssistant(item.id);
                if (success != true) {
                  showAppSnackBar(
                    context,
                    message: l10n.assistantSettingsAtLeastOneAssistantRequired,
                    type: NotificationType.warning,
                  );
                }
              }
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? cs.error.withOpacity(0.22) : cs.error.withOpacity(0.14),
                // 14 无精确 token，保留字面量
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.error.withOpacity(0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xs),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Lucide.Trash2, color: cs.error, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      l10n.assistantSettingsDeleteButton,
                      style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// 新增助手弹层：输入名字 → 返回 trim 后的非空名字。
///
/// 用 `showAppSheet` 承载（统一 SafeArea + 顶部圆角 + 键盘避让），
/// 但**内容保持自建**——本弹层是「居中标题 + 左右双按钮」，
/// 而 `AppSheet` 的 `title` 是左对齐的，套上去会改视觉。
/// 因此把手（grabber）需要自己画（`AppSheet` 组件才会自动加）。
Future<String?> _showAddAssistantSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final result = await showAppSheet<String>(
    context: context,
    builder: Padding(
      padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppRadius.circular),
              ),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          Center(
            child: Text(
              l10n.assistantSettingsAddSheetTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: AppGap.md),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.assistantSettingsAddSheetHint,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : const Color(0xFFF2F3F5),
              border: _fieldBorder(context, 0.4, Theme.of(context).colorScheme.outlineVariant),
              enabledBorder:
                  _fieldBorder(context, 0.4, Theme.of(context).colorScheme.outlineVariant),
              focusedBorder: _fieldBorder(context, 0.5, Theme.of(context).colorScheme.primary),
            ),
            onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
          ),
          const SizedBox(height: AppGap.md),
          Row(
            children: [
              Expanded(
                child: _IosOutlineButton(
                  label: l10n.assistantSettingsAddSheetCancel,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppGap.sm),
              Expanded(
                child: _IosFilledButton(
                  label: l10n.assistantSettingsAddSheetSave,
                  onTap: () => Navigator.of(context).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  final trimmed = (result ?? '').trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

OutlineInputBorder _fieldBorder(BuildContext context, double opacity, Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: color.withOpacity(opacity)),
  );
}

Future<bool?> _confirmDelete(BuildContext context, AppLocalizations l10n) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(l10n.assistantSettingsDeleteDialogTitle),
        content: Text(l10n.assistantSettingsDeleteDialogContent),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.assistantSettingsDeleteDialogCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.assistantSettingsDeleteDialogConfirm,
                style: TextStyle(color: cs.error)),
          ),
        ],
      );
    },
  );
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({required this.item, this.size = 40});
  final Assistant item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final av = (item.avatar ?? '').trim();
    if (av.isNotEmpty) {
      if (av.startsWith('http')) {
        return FutureBuilder<String?>(
          future: AvatarCache.getPath(av),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p != null && File(p).existsSync()) {
              return ClipOval(
                child: Image(
                  image: FileImage(File(p)),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            }
            return ClipOval(
              child: Image.network(
                av,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _initial(cs),
              ),
            );
          },
        );
      } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
        final fixed = SandboxPathResolver.fix(av);
        final f = File(fixed);
        if (f.existsSync()) {
          return ClipOval(
            child: Image(
              image: FileImage(f),
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
        return _initial(cs);
      } else {
        return _emoji(cs, av);
      }
    }
    return _initial(cs);
  }

  Widget _initial(ColorScheme cs) {
    final letter = item.name.isNotEmpty ? item.name.characters.first : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _emoji(ColorScheme cs, String emoji) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(emoji.characters.take(1).toString(), style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// 描边按钮：按压效果与触觉交给 `IosTactileRow`，本组件只管外观。
class _IosOutlineButton extends StatelessWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosTactileRow(
      onTap: onTap,
      pressedScale: 0.97,
      releaseDelay: const Duration(milliseconds: 80),
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(vertical: AppGap.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.primary.withOpacity(0.5)),
        ),
        child: Text(label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// 实心按钮：同上。
class _IosFilledButton extends StatelessWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosTactileRow(
      onTap: onTap,
      pressedScale: 0.97,
      releaseDelay: const Duration(milliseconds: 80),
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(vertical: AppGap.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: cs.primary, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Text(label, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppGap.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: AppGap.xxxs),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.circular),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
