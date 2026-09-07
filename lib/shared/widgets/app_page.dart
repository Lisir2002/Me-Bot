import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';
import 'app_states.dart';
import 'ios_tactile.dart';

// ──────────────────────────────────────────────────────────────
// AppPage — 页面骨架模板（区域槽位引擎）
//
// 一个页面 = 声明各区域放什么，引擎自动拼装 Scaffold。
// 槽位一览：
//   顶栏区   : title / leading / showBack / actions
//   分段区   : segments(segmentsMode=top→AppBar.bottom TabBar | bottom→页内底部分段)
//   内容区   : body / states(AsyncSnapshot 三态) / scrollable / bodyPadding
//   底栏区   : bottom（自定义底部，如操作条/导航栏）
//   FAB/抽屉 : floatingActionButton / drawer / endDrawer
//
// 内容优先级：states > segments > body
// ──────────────────────────────────────────────────────────────

/// 一个分段：label + 内容 builder
class AppSegment {
  final String label;
  final Widget Function(BuildContext context) body;

  /// 页内 bottom 分段的图标（选中态高亮）
  final IconData? icon;
  final IconData? selectedIcon;

  const AppSegment({
    required this.label,
    required this.body,
    this.icon,
    this.selectedIcon,
  });
}

/// 分段落点：顶栏 TabBar 或 页内底部 NavigationBar
enum AppSegmentMode { top, bottom }

/// 三态状态机配置（AsyncSnapshot 驱动）
class AppPageStates<T> {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) buildData;
  final bool Function(T data)? emptyWhen;
  final String emptyMessage;
  final String? emptyHint;
  final Future<void> Function()? onRetry;
  final String? loadingMessage;

  const AppPageStates({
    required this.load,
    required this.buildData,
    this.emptyWhen,
    this.emptyMessage = '暂无内容',
    this.emptyHint,
    this.onRetry,
    this.loadingMessage,
  });
}

class AppPage extends StatefulWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final EdgeInsetsGeometry bodyPadding;
  final bool scrollable;
  final bool safeArea;
  final Color? backgroundColor;

  /// 分段（有则优先于 body）
  final List<AppSegment>? segments;
  final AppSegmentMode segmentsMode;

  /// 三态状态机（可选，包住内容区）
  final AppPageStates? states;

  /// 自定义底部槽位
  final Widget? bottom;

  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.showBack = true,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.bodyPadding = AppPagePadding.hv,
    this.scrollable = true,
    this.safeArea = true,
    this.backgroundColor,
    this.segments,
    this.segmentsMode = AppSegmentMode.top,
    this.states,
    this.bottom,
  });

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  int _bottomIndex = 0;

  /// 是否片状内容（分段由引擎自管，无需外层 padding/scrollable）
  bool get _usesSegments => widget.segments != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final effectiveLeading = widget.leading ??
        (widget.showBack
            ? Tooltip(
                message: MaterialLocalizations.of(context).backButtonTooltip,
                child: IosIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  minSize: 44,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              )
            : null);

    // ── 内容组装 ──
    Widget content = _buildContent(context);

    // states 包裹内容区
    if (widget.states != null) {
      content = _StatesScope(config: widget.states!, child: content);
    }

    // 非分段内容：外层 padding + 可选滚动
    Widget bodyContent = content;
    if (!_usesSegments) {
      bodyContent = Padding(
        padding: widget.bodyPadding,
        child: widget.scrollable
            ? ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [content],
              )
            : content,
      );
    }

    // ── AppBar.bottom（top 分段）──
    PreferredSizeWidget? appBarBottom;
    if (widget.segments != null && widget.segmentsMode == AppSegmentMode.top) {
      appBarBottom = TabBar(
        indicatorColor: cs.primary,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurface.withOpacity(0.6),
        tabs: [for (final s in widget.segments!) Tab(text: s.label)],
      );
    }

    // ── bottom 槽位（bottom 分段自动构造 NavigationBar）──
    Widget? bottomSlot = widget.bottom;
    if (widget.segments != null && widget.segmentsMode == AppSegmentMode.bottom) {
      final segs = widget.segments!;
      bottomSlot = NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (i) => setState(() => _bottomIndex = i),
        elevation: 0,
        backgroundColor: cs.surface,
        destinations: [
          for (final s in segs)
            NavigationDestination(
              icon: Icon(s.icon ?? Icons.circle_outlined),
              selectedIcon: Icon(s.selectedIcon ?? s.icon ?? Icons.circle),
              label: s.label,
            ),
        ],
      );
    }

    final scaffold = Scaffold(
      backgroundColor: widget.backgroundColor ?? cs.surface,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        leadingWidth: effectiveLeading != null ? 56 : null,
        leading: effectiveLeading,
        title: Text(widget.title),
        actions: widget.actions,
        bottom: appBarBottom,
      ),
      body: widget.safeArea ? SafeArea(child: bodyContent) : bodyContent,
      bottomNavigationBar: bottomSlot,
      floatingActionButton: widget.floatingActionButton,
    );

    // top 分段需要 DefaultTabController 驱动 TabBar + TabBarView
    if (widget.segments != null && widget.segmentsMode == AppSegmentMode.top) {
      return DefaultTabController(length: widget.segments!.length, child: scaffold);
    }
    return scaffold;
  }

  /// 根据 segments / body 组装内容体
  Widget _buildContent(BuildContext context) {
    final segs = widget.segments;
    if (segs == null) return widget.body;

    switch (widget.segmentsMode) {
      case AppSegmentMode.top:
        return TabBarView(
          children: [for (final s in segs) s.body(context)],
        );
      case AppSegmentMode.bottom:
        return segs[_bottomIndex.clamp(0, segs.length - 1)].body(context);
    }
  }
}

// ──────────────────────────────────────────────────────────────
// 内部：AsyncSnapshot 三态作用域（自管 future）
// ──────────────────────────────────────────────────────────────
class _StatesScope extends StatefulWidget {
  final AppPageStates config;
  final Widget? child;
  const _StatesScope({required this.config, this.child});

  @override
  State<_StatesScope> createState() => _StatesScopeState();
}

class _StatesScopeState extends State<_StatesScope> {
  Future<dynamic>? _future;

  Future<dynamic> _fetch() => widget.config.load();

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(_StatesScope old) {
    super.didUpdateWidget(old);
    if (old.config != widget.config && widget.config != null) {
      _future = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _future = _fetch());
      });
    }
  }

  void _retry() {
    setState(() => _future = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoading(
            message: cfg.loadingMessage,
            verticalPadding: widget.child == null ? 60 : 12,
          );
        }
        if (snapshot.hasError) {
          return AppError(message: snapshot.error.toString(), onRetry: cfg.onRetry ?? _retry);
        }
        final data = snapshot.data;
        if (data != null && (cfg.emptyWhen?.call(data) ?? false)) {
          return AppEmpty(
            message: cfg.emptyMessage,
            hint: cfg.emptyHint,
            action: cfg.onRetry == null
                ? null
                : FilledButton.tonal(onPressed: cfg.onRetry, child: const Text('重试')),
          );
        }
        return cfg.buildData(context, data);
      },
    );
  }
}