// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../models/message_part.dart';

/// 消息出现动画 —— 新消息从底部滑入 + 淡入
///
/// duration 300ms，curve easeOutCubic，仅对新挂载的子树播放一次。
class MessageSlideIn extends StatefulWidget {
  final Widget child;
  const MessageSlideIn({super.key, required this.child});

  @override
  State<MessageSlideIn> createState() => _MessageSlideInState();
}

class _MessageSlideInState extends State<MessageSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();
  late final Animation<Offset> _offset = Tween(
    begin: const Offset(0, 0.06), // 约 20px
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offset,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

/// 工具调用状态变化微动画
///
/// running：旋转脉冲；success：对勾弹出；error：红色抖动。
class ToolCallStatusAnimation extends StatelessWidget {
  final ToolCallStatus status;
  final Widget child;
  const ToolCallStatusAnimation({
    super.key,
    required this.status,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ToolCallStatus.running:
        return _Pulse(child: child);
      case ToolCallStatus.success:
        return _PopIn(child: child);
      case ToolCallStatus.error:
        return _Shake(child: child);
      default:
        return child;
    }
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.6, end: 1.0).animate(_c),
      child: widget.child,
    );
  }
}

class _PopIn extends StatelessWidget {
  final Widget child;
  const _PopIn({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, child) =>
          Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

class _Shake extends StatefulWidget {
  final Widget child;
  const _Shake({required this.child});

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dx = 4 * (1 - _c.value) * (_c.value * 2 > 1 ? -1 : 1);
        return Transform.translate(offset: Offset(dx, 0), child: widget.child);
      },
    );
  }
}

/// 思考块展开/折叠高度平滑过渡
class ThinkingExpandAnimation extends StatelessWidget {
  final bool expanded;
  final Widget child;
  const ThinkingExpandAnimation({
    super.key,
    required this.expanded,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      crossFadeState:
          expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: child,
      secondChild: const SizedBox.shrink(),
    );
  }
}
