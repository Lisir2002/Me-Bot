import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/card_surface.dart';
import '../../../shared/widgets/ios_switch.dart';

/// 文件大小格式化（B / KB / MB / GB）。与 backup_page 的私有版保持一致。
String storageFormatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
  return '$bytes B';
}

/// iOS 风格分组卡片容器。
class StorageSectionCard extends StatelessWidget {
  const StorageSectionCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = storageCardBackground(theme);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: storageCardBorder(context, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  }
}

/// 卡片背景色：浅色为近白，深色为半透明白。
Color storageCardBackground(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? Colors.white10
      : Colors.white.withOpacity(0.96);
}

/// 细微黑边：浅色下用低透明度黑，深色下用低透明度白，保证卡片轮廓清晰但不刺眼。
Border storageCardBorder(BuildContext context, {double width = 0.8}) {
  return AppCardSurface.border(context, width: width);
}

/// iOS 风格分组标题。
class StorageSectionHeader extends StatelessWidget {
  const StorageSectionHeader(this.text, {super.key, this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 2 : 18, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withOpacity(0.8),
        ),
      ),
    );
  }
}

/// 行间分隔线，缩进对齐图标槽位。
class StorageDivider extends StatelessWidget {
  const StorageDivider({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 6,
      thickness: 0.6,
      indent: 54,
      endIndent: 12,
      color: cs.outlineVariant.withOpacity(0.18),
    );
  }
}

/// 触点反馈的按压颜色过渡包装。
class StorageAnimatedPressColor extends StatelessWidget {
  const StorageAnimatedPressColor({
    super.key,
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = isDark ? Colors.black : Colors.white;
    final target = pressed ? (Color.lerp(base, a, 0.55) ?? base) : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

/// 触点行。
class StorageTactileRow extends StatefulWidget {
  const StorageTactileRow({
    super.key,
    required this.builder,
    this.onTap,
    this.pressedScale = 1.0,
    this.haptics = true,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;

  @override
  State<StorageTactileRow> createState() => _StorageTactileRowState();
}

class _StorageTactileRowState extends State<StorageTactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics) {
                context.read<SettingsProvider>().hapticsOnListItemTap
                    ? Haptics.soft()
                    : null;
              }
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.builder(_pressed),
      ),
    );
  }
}

/// 图标行（带可选 detail 与右箭头）。
class StorageNavRow extends StatelessWidget {
  const StorageNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.detailText,
    this.detailBuilder,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? detailText;
  final Widget Function(BuildContext ctx)? detailBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final interactive = onTap != null;
    return StorageTactileRow(
      onTap: onTap,
      pressedScale: 1.0,
      haptics: false,
      builder: (pressed) {
        final baseColor = cs.onSurface.withOpacity(0.9);
        return StorageAnimatedPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                      child: detailBuilder!(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText!,
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 开关行。
class StorageSwitchRow extends StatelessWidget {
  const StorageSwitchRow({
    super.key,
    this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData? icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StorageTactileRow(
      onTap: () => onChanged(!value),
      pressedScale: 1.0,
      builder: (pressed) {
        final baseColor = cs.onSurface.withOpacity(0.9);
        return StorageAnimatedPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                if (icon != null) ...[
                  SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
                IosSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 图标触点按钮（AppBar 用）。
class StorageTactileIconButton extends StatefulWidget {
  const StorageTactileIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
    this.semanticLabel,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final String? semanticLabel;

  @override
  State<StorageTactileIconButton> createState() => _StorageTactileIconButtonState();
}

class _StorageTactileIconButtonState extends State<StorageTactileIconButton> {
  bool _pressed = false;
  void _safeOnTap() {
    try {
      Haptics.light();
      widget.onTap();
    } catch (e, s) {
      debugPrint('[StorageTactileIconButton] onTap failed: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final press = base.withOpacity(0.7);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _safeOnTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(widget.icon, size: widget.size, color: _pressed ? press : base),
        ),
      ),
    );
  }
}

/// 描边按钮。
class StorageOutlineButton extends StatefulWidget {
  const StorageOutlineButton({super.key, this.icon, required this.label, required this.onTap});
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  @override
  State<StorageOutlineButton> createState() => _StorageOutlineButtonState();
}

class _StorageOutlineButtonState extends State<StorageOutlineButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _safeOnTap() {
    try {
      Haptics.soft();
      widget.onTap();
    } catch (e, s) {
      debugPrint('[StorageOutlineButton] onTap failed: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: _safeOnTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 17, color: cs.primary),
                const SizedBox(width: 6),
              ],
              Text(widget.label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实心按钮。
class StorageFilledButton extends StatefulWidget {
  const StorageFilledButton({super.key, this.icon, required this.label, required this.onTap, this.bg});
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final Color? bg;
  @override
  State<StorageFilledButton> createState() => _StorageFilledButtonState();
}

class _StorageFilledButtonState extends State<StorageFilledButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _safeOnTap() {
    try {
      Haptics.soft();
      widget.onTap();
    } catch (e, s) {
      debugPrint('[StorageFilledButton] onTap failed: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.bg ?? cs.primary;
    final fg = widget.bg == null ? cs.onPrimary : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: _safeOnTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(widget.label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}