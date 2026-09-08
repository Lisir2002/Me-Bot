import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/haptics.dart';

/// iOS-style icon button: no ripple, color tween on press, no scale.
class IosIconButton extends StatefulWidget {
  const IosIconButton({
    super.key,
    this.icon,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.size = 20,
    this.padding = const EdgeInsets.all(6),
    this.color,
    this.pressedColor,
    this.minSize,
    this.semanticLabel,
    this.enabled = true,
    this.haptics = false,
  }) : assert(icon != null || builder != null, 'Either icon or builder must be provided');

  final IconData? icon;
  // Builder receives the current animated color to render custom child (e.g., SVG).
  final Widget Function(Color color)? builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;
  final EdgeInsets padding;
  final Color? color; // base color; defaults to theme onSurface
  final Color? pressedColor; // override pressed color; defaults to blend with primary
  final double? minSize; // min tap target (e.g., 44 for AppBar)
  final String? semanticLabel;
  final bool enabled;

  /// 点按/长按时是否给 `Haptics.light()` 触觉反馈。
  ///
  /// 默认 `false`（保持本组件既有行为不变，属纯增量参数）。
  /// 项目里各页原先的私有 `_TactileIconButton` 普遍会在点按时触发触觉，
  /// 迁移到本组件时应显式传 `haptics: true` 以保住手感
  /// （`StorageTactileIconButton` 也是无条件触觉，未受设置开关约束）。
  final bool haptics;

  @override
  State<IosIconButton> createState() => _IosIconButtonState();
}

class _IosIconButtonState extends State<IosIconButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Respect provided color opacity when enabled; only dim when disabled.
    final Color base = () {
      if (widget.color != null) {
        return widget.enabled
            ? widget.color!
            : widget.color!.withOpacity(widget.color!.opacity * 0.45);
      }
      return theme.colorScheme.onSurface.withOpacity(widget.enabled ? 1 : 0.45);
    }();
    // On press, shift icon color toward white (light theme) or black (dark theme)
    // to get a subtle lighter/gray look, unless overridden via pressedColor.
    final bool isDark = theme.brightness == Brightness.dark;
    final Color pressTarget = widget.pressedColor ?? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.35) ?? base);
    final Color hoverTarget = Color.lerp(base, isDark ? Colors.black : Colors.white, 0.20) ?? base;
    final Color target = _pressed ? pressTarget : (_hovered ? hoverTarget : base);

    final child = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) {
        final c = color ?? base;
        if (widget.builder != null) {
          return widget.builder!(c);
        }
        return Icon(widget.icon, size: widget.size, color: c, semanticLabel: widget.semanticLabel);
      },
    );

    // Subtle hover background for desktop/web
    final Color bgTarget = _pressed
        ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08))
        : (_hovered
            ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06))
            : Colors.transparent);

    final content = Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: (widget.enabled && (widget.onTap != null || widget.onLongPress != null))
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (widget.enabled && (widget.onTap != null || widget.onLongPress != null)) ? (_) => setState(() => _pressed = true) : null,
          onTapUp: (widget.enabled && (widget.onTap != null || widget.onLongPress != null)) ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: (widget.enabled && (widget.onTap != null || widget.onLongPress != null)) ? () => setState(() => _pressed = false) : null,
          onTap: widget.enabled
              ? () {
                  if (widget.haptics) Haptics.light();
                  widget.onTap?.call();
                }
              : null,
          onLongPress: widget.enabled
              ? () {
                  if (widget.haptics) Haptics.light();
                  widget.onLongPress?.call();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: bgTarget,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: widget.padding,
              child: child,
            ),
          ),
        ),
      ),
    );

    if (widget.minSize != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minSize!, minHeight: widget.minSize!),
        child: Center(child: content),
      );
    }
    return content;
  }
}

/// iOS-style card press effect: background color tween on press, no ripple, no scale.
class IosCardPress extends StatefulWidget {
  const IosCardPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.baseColor,
    this.pressedBlendStrength,
    this.padding,
    this.pressedScale,
    this.duration,
    this.haptics = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  // 0..1; how much to blend towards surface tint on press
  final double? pressedBlendStrength;
  final EdgeInsetsGeometry? padding;
  // Optional subtle scale when pressed (e.g., 0.98). Defaults to 1.0 (no scale).
  final double? pressedScale;
  // Optional custom animation duration for color/scale tween.
  final Duration? duration;
  // Whether to perform a soft haptic on tap (also gated by settings/global toggles)
  final bool haptics;

  @override
  State<IosCardPress> createState() => _IosCardPressState();
}

class _IosCardPressState extends State<IosCardPress> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color base = widget.baseColor ?? (isDark ? Colors.white10 : cs.surface);
    final double k = widget.pressedBlendStrength ?? (isDark ? 0.14 : 0.12);
    final Color pressTarget = Color.lerp(base, isDark ? Colors.white : Colors.black, k) ?? base;
    final Color hoverTarget = Color.lerp(base, isDark ? Colors.white : Colors.black, k * 0.7) ?? base;
    final Color target = _pressed ? pressTarget : (_hovered ? hoverTarget : base);
    final double scale = _pressed ? (widget.pressedScale ?? 1.0) : 1.0;
    final Duration dur = widget.duration ?? const Duration(milliseconds: 200);

    final content = widget.padding == null ? widget.child : Padding(padding: widget.padding!, child: widget.child);

    return MouseRegion(
      cursor: (widget.onTap != null || widget.onLongPress != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (widget.onTap != null || widget.onLongPress != null) ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (widget.onTap != null || widget.onLongPress != null) ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: (widget.onTap != null || widget.onLongPress != null) ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                final sp = context.read<SettingsProvider>();
                if (widget.haptics && sp.hapticsOnCardTap) Haptics.soft();
                widget.onTap!.call();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: scale,
          duration: dur,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: target,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// IosTactileRow / IosPressColor —— 「自绘按压效果」用的两个原语
//
// IosCardPress 的按压效果是固定的「底色向白/黑混合」，只适合纯底色卡；
// 当行卡需要 透明底+文字变色、自绘边框/覆盖层 时，它表达不了。
// 这两个组件把按压态交还给调用方：
//   IosTactileRow  —— 只负责手势/触觉/可选缩放，把 pressed 回传给 builder
//   IosPressColor  —— 只负责文字/图标颜色的按压过渡（透明底不变）
// 二者可组合使用：IosTactileRow(builder: (_, pressed) => IosPressColor(...))
// ──────────────────────────────────────────────────────────────

/// 无背景绘制的通用可按压行/卡容器，把按压态回传给 builder。
///
/// 与 [IosCardPress] 的分工：
/// - IosCardPress：整体底色按压过渡（固定向白/黑混合），适合纯底色卡
/// - IosTactileRow：自绘边框/覆盖层/文字变色的行卡
///
/// 触觉反馈沿用「设置 → 列表项点按触觉」开关（[haptics] 可整体关闭）。
class IosTactileRow extends StatefulWidget {
  const IosTactileRow({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.pressedScale,
    this.releaseDelay = Duration.zero,
    this.haptics = true,
  });

  /// `pressed` 为当前是否按压中，调用方据此自绘按压效果。
  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按压时缩放（如 0.98）；null = 不缩放。
  final double? pressedScale;

  /// 抬起后延迟复位按压态，让按压色多停留一瞬（如 120ms）。
  final Duration releaseDelay;

  /// 是否在点按时给软触觉反馈（仍受 设置→列表项触觉 开关约束）。
  final bool haptics;

  @override
  State<IosTactileRow> createState() => _IosTactileRowState();
}

class _IosTactileRowState extends State<IosTactileRow> {
  bool _pressed = false;
  void _set(bool v) { if (_pressed != v) setState(() => _pressed = v); }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled
            ? (_) {
                if (widget.releaseDelay == Duration.zero) {
                  _set(false);
                } else {
                  Future.delayed(widget.releaseDelay, () { if (mounted) _set(false); });
                }
              }
            : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptics && context.read<SettingsProvider>().hapticsOnListItemTap) {
                  Haptics.soft();
                }
                widget.onTap!.call();
              },
        child: AnimatedScale(
          scale: _pressed ? (widget.pressedScale ?? 1.0) : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: widget.builder(context, _pressed),
        ),
      ),
    );
  }
}

/// 按压时文字/图标颜色的过渡（向暗/亮色混合 55%），无背景、无缩放。
///
/// 与 [IosTactileRow] 组合使用：
/// ```dart
/// IosTactileRow(
///   onTap: ...,
///   builder: (ctx, pressed) => IosPressColor(
///     pressed: pressed,
///     base: cs.onSurface.withOpacity(0.9),
///     builder: (c) => Text(title, style: TextStyle(color: c)),
///   ),
/// )
/// ```
class IosPressColor extends StatelessWidget {
  const IosPressColor({
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
    final target = pressed ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base) : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}
