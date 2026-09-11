// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../data/conversation_data_source.dart';
import '../models/conversation_style.dart';
import '../models/style_settings.dart';
import 'style_error_boundary.dart';
import 'style_renderer_registry.dart';
import 'style_switcher.dart';

/// 对话视图容器 —— 持有 StyleSwitcher，根据当前样式渲染对应 UI
///
/// 这是样式系统的入口 widget。它持有：
/// - ConversationDataSource（数据层，样式切换时不变）
/// - StyleSwitcher（样式切换控制器）
/// - ConversationUIState（跨样式 UI 状态）
///
/// 公共组件（输入框、发送按钮、AppBar）在此容器中保持不变，
/// 只有消息列表区域随样式切换。
class ConversationView extends StatefulWidget {
  /// 数据源
  final ConversationDataSource dataSource;

  /// 渲染器注册表
  final StyleRendererRegistry registry;

  /// 初始样式
  final ConversationStyle initialStyle;

  /// 样式设置
  final StyleSettings settings;

  /// 输入框 widget（公共组件）
  final Widget? inputBar;

  /// AppBar 标题
  final String? title;

  /// 样式切换回调
  final void Function(ConversationStyle)? onStyleChanged;

  const ConversationView({
    super.key,
    required this.dataSource,
    required this.registry,
    this.initialStyle = ConversationStyle.classicBubble,
    this.settings = const StyleSettings(),
    this.inputBar,
    this.title,
    this.onStyleChanged,
  });

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  late final StyleSwitcher _switcher;

  @override
  void initState() {
    super.initState();
    _switcher = StyleSwitcher(
      registry: widget.registry,
      dataSource: widget.dataSource,
      initialStyle: widget.initialStyle,
    );
    _switcher.initialize();
    _switcher.addListener(_onSwitcherChanged);
  }

  @override
  void dispose() {
    _switcher.removeListener(_onSwitcherChanged);
    _switcher.dispose();
    super.dispose();
  }

  void _onSwitcherChanged() {
    setState(() {});
    widget.onStyleChanged?.call(_switcher.currentStyle);
  }

  /// 外部调用：切换样式
  void switchStyle(ConversationStyle style) {
    _switcher.switchTo(style);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 样式切换指示器（切换中显示）
        if (_switcher.isSwitching)
          const LinearProgressIndicator(minHeight: 2),

        // 消息列表区域（随样式切换）
        Expanded(
          child: StyleErrorBoundary(
            style: _switcher.currentStyle,
            onFallback: () =>
                _switcher.recordFallback(_switcher.currentStyle),
            builder: (context) => _switcher.buildCurrent(context),
          ),
        ),

        // 输入框（公共组件，不随样式切换）
        if (widget.inputBar != null) widget.inputBar!,
      ],
    );
  }
}

/// 样式切换按钮 —— 放在 AppBar 中，点击弹出样式选择底部 Sheet
class StyleSwitcherButton extends StatelessWidget {
  final ConversationStyle currentStyle;
  final void Function(ConversationStyle) onStyleSelected;

  const StyleSwitcherButton({
    super.key,
    required this.currentStyle,
    required this.onStyleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.palette_outlined),
      tooltip: '切换对话样式',
      onPressed: () => _showStyleSheet(context),
    );
  }

  void _showStyleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StyleSelectionSheet(
        currentStyle: currentStyle,
        onStyleSelected: (style) {
          Navigator.pop(context);
          onStyleSelected(style);
        },
      ),
    );
  }
}

/// 样式选择底部 Sheet
class StyleSelectionSheet extends StatelessWidget {
  final ConversationStyle currentStyle;
  final void Function(ConversationStyle) onStyleSelected;

  const StyleSelectionSheet({
    super.key,
    required this.currentStyle,
    required this.onStyleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final styles = StyleMetaRegistry.concreteStyles;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择对话样式',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '当前：${StyleMetaRegistry.get(currentStyle).displayName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: styles.length,
              itemBuilder: (context, index) {
                final meta = styles[index];
                final isSelected = meta.style == currentStyle;
                return _StyleCard(
                  meta: meta,
                  isSelected: isSelected,
                  onTap: () => onStyleSelected(meta.style),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final StyleMeta meta;
  final bool isSelected;
  final VoidCallback onTap;

  const _StyleCard({
    required this.meta,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    meta.number,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle,
                      size: 14, color: theme.colorScheme.primary),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              meta.displayName,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                meta.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
