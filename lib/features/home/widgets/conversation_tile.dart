import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/conversation.dart';
import '../../../shared/widgets/ios_tactile.dart';

/// 对话条目组件（从 side_drawer 提取）
/// 保留原有行为：选中高亮、loading 点、hover、onTap/onLongPress/onSecondaryTap
class ConversationTile extends StatefulWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.textColor,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.selected = false,
    this.loading = false,
    this.embedded = false,
    this.showPinIcon = false,
  });

  final Conversation conversation;
  final Color textColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final bool selected;
  final bool loading;
  final bool embedded;
  final bool showPinIcon;

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  bool _hovered = false;
  bool get _isDesktop => defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color tileColor;
    if (widget.embedded) {
      // 平板嵌入模式：保留选中高亮，其余透明
      tileColor = widget.selected ? cs.primary.withOpacity(0.16) : Colors.transparent;
    } else {
      tileColor = widget.selected ? cs.primary.withOpacity(0.12) : cs.surface;
    }
    final base = _isDesktop && !widget.selected && _hovered
        ? (widget.embedded ? cs.primary.withOpacity(0.08) : cs.surface.withOpacity(0.9))
        : tileColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          if (_isDesktop) {
            widget.onSecondaryTap?.call(details.globalPosition);
          }
        },
        onLongPress: () {
          if (_isDesktop) return;
          widget.onLongPress?.call();
        },
        child: MouseRegion(
          onEnter: (_) { if (_isDesktop) setState(() => _hovered = true); },
          onExit: (_) { if (_isDesktop) setState(() => _hovered = false); },
          cursor: _isDesktop ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: IosCardPress(
            baseColor: base,
            borderRadius: BorderRadius.circular(16),
            haptics: false,
            onTap: widget.onTap,
            onLongPress: _isDesktop ? null : widget.onLongPress,
            padding: EdgeInsets.fromLTRB(_isDesktop ? 14 : 14, _isDesktop ? 9 : 10, 8, _isDesktop ? 9 : 10),
            child: Row(
              children: [
                if (widget.showPinIcon) ...[
                  Icon(
                    Lucide.Pin,
                    size: 12,
                    color: cs.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    widget.conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _isDesktop ? 14 : 15,
                      color: widget.textColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.loading) ...[
                  const SizedBox(width: 8),
                  const ConversationTileLoadingDot(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 对话加载中的脉冲圆点
class ConversationTileLoadingDot extends StatefulWidget {
  const ConversationTileLoadingDot({super.key});

  @override
  State<ConversationTileLoadingDot> createState() => _ConversationTileLoadingDotState();
}

class _ConversationTileLoadingDotState extends State<ConversationTileLoadingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
      ),
    );
  }
}
