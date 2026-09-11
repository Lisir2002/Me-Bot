import 'dart:async';

import 'package:flutter/material.dart';
import '../../../l10n/build_context_l10n.dart';
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
  ConversationViewState createState() => ConversationViewState();
}

/// ConversationView 的公开 State 类型
///
/// 外部（如主对话页）可通过 `GlobalKey<ConversationViewState>` 持有实例，
/// 调用 [switchStyle] 在不重建 widget 树的前提下切换样式，
/// 从而保留数据、流式状态与渲染器内部状态。
class ConversationViewState extends State<ConversationView> {
  late final StyleSwitcher _switcher;

  /// 订阅消息流，数据变化（版本切换/删除/截断）时刷新容器 chrome
  StreamSubscription? _msgSub;

  /// 是否处于多选模式（容器 UI 状态，不经 dataSource 持久化）
  bool _selectionMode = false;

  /// 已选中消息 ID 集合（UI 状态；分享/删除执行经 dataSource）
  final Set<String> _selectedIds = <String>{};

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
    // 数据层任何变更都驱动容器层（版本导航/截断线/已选数量）重绘
    _msgSub = widget.dataSource.messageStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
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

  /// 当前需要显示版本导航的分组：取最后一个多版本分组。
  ///
  /// 容器层只提供单一版本切换控件，对应"当前活跃"的可回退版本组；
  /// 单版本分组或无版本分组时返回 null，不显示控件。
  ConversationVersionGroup? _activeVersionGroup(ConversationDataSource ds) {
    ConversationVersionGroup? found;
    for (final g in ds.versionGroups) {
      if (g.hasMultiple) found = g;
    }
    return found;
  }

  /// 退出多选并清空选中集合
  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 分享所选：经 dataSource 解析并交宿主展示分享面板
  Future<void> _shareSelected() async {
    final ids = _selectedIds.toList(growable: false);
    _exitSelection();
    await widget.dataSource.shareSelectedMessages(ids);
  }

  /// 删除所选：经 dataSource 批量删除
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList(growable: false);
    _exitSelection();
    await widget.dataSource.deleteMessages(ids);
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.dataSource;
    final truncIdx = ds.truncatePositionIndex;
    final hasMessages = ds.currentMessages.isNotEmpty;
    final hasVersionNav = _activeVersionGroup(ds) != null;
    // 仅在有消息 / 有版本导航 / 多选进行中时渲染顶部工具行，避免空会话占位
    final showTopBar = _selectionMode || hasMessages || hasVersionNav;

    return Column(
      children: [
        // 样式切换指示器（切换中显示）
        if (_switcher.isSwitching)
          const LinearProgressIndicator(minHeight: 2),

        // 容器层能力条：版本导航 / 选择入口，或多选操作条
        if (showTopBar) _buildTopBar(context),

        // 消息列表区域（截断线 + 随样式切换的渲染器产出）
        Expanded(
          child: Column(
            children: [
              // 截断线：有截断时在消息流顶部提示"此处之前为已截断上下文"
              if (truncIdx != null) _buildTruncateStrip(context),
              Expanded(child: _buildSwitcherArea()),
            ],
          ),
        ),

        // 输入框（公共组件，不随样式切换）
        if (widget.inputBar != null) widget.inputBar!,
      ],
    );
  }

  /// 样式切换区域：保持原有 AnimatedSwitcher 过渡 + 错误边界，
  /// 渲染器对容器层能力完全无感知。
  Widget _buildSwitcherArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      // 对称缩放：新样式淡入并由 0.98 放大到 1.04，旧样式反向淡出并缩小
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.04).animate(curved),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        // key 绑定当前样式，AnimatedSwitcher 据此识别新旧并播放过渡
        key: ValueKey<ConversationStyle>(_switcher.currentStyle),
        child: StyleErrorBoundary(
          style: _switcher.currentStyle,
          onFallback: () =>
              _switcher.recordFallback(_switcher.currentStyle),
          builder: (context) => _switcher.buildCurrent(context),
        ),
      ),
    );
  }

  /// 顶部工具行：
  /// - 多选模式：关闭 / 已选数量 / 全选 / 分享所选 / 删除所选；
  /// - 普通模式：版本上一版/下一版 + "版本 i/total"，右侧"选择消息"入口。
  Widget _buildTopBar(BuildContext context) {
    final l10n = context.l10n;
    final ds = widget.dataSource;
    final cs = Theme.of(context).colorScheme;

    if (_selectionMode) {
      return Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.convStyleCancelSelection,
              onPressed: _exitSelection,
            ),
            Text(l10n.convStyleSelectedCount(_selectedIds.length)),
            const Spacer(),
            TextButton(
              onPressed: _selectedIds.length == ds.currentMessages.length
                  ? null
                  : () => setState(() => _selectedIds
                    ..clear()
                    ..addAll(ds.currentMessages.map((m) => m.id))),
              child: Text(l10n.convStyleSelectAll),
            ),
            TextButton(
              onPressed:
                  _selectedIds.isEmpty ? null : () => _shareSelected(),
              child: Text(l10n.convStyleShareSelected),
            ),
            TextButton(
              onPressed:
                  _selectedIds.isEmpty ? null : () => _deleteSelected(),
              child: Text(l10n.convStyleDeleteSelected),
            ),
          ],
        ),
      );
    }

    final group = _activeVersionGroup(ds);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (group != null) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.convStylePrevVersion,
              onPressed: group.selectedIndex > 0
                  ? () => ds.setSelectedVersion(
                      group.groupId, group.selectedIndex - 1)
                  : null,
            ),
            Text(l10n.convStyleVersionOf(
                group.selectedIndex + 1, group.total)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.convStyleNextVersion,
              onPressed: group.selectedIndex < group.total - 1
                  ? () => ds.setSelectedVersion(
                      group.groupId, group.selectedIndex + 1)
                  : null,
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: l10n.convStyleSelectMessages,
            onPressed: ds.currentMessages.isEmpty
                ? null
                : () => setState(() {
                      _selectionMode = true;
                      _selectedIds.clear();
                    }),
          ),
        ],
      ),
    );
  }

  /// 截断线分隔提示：两侧细线 + 居中文案（复用 homePageClearContext）。
  Widget _buildTruncateStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget line() =>
        Expanded(child: Divider(color: cs.outlineVariant, thickness: 1));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              context.l10n.homePageClearContext,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          line(),
        ],
      ),
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
      tooltip: context.l10n.convStyleSwitchStyleTooltip,
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
            context.l10n.convStyleSettingsTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${context.l10n.convStyleCurrent}: '
            '${currentStyle.l10nName(context.l10n)}',
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
              meta.style.l10nName(context.l10n),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                meta.style.l10nDescription(context.l10n),
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
