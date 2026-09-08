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
//
// ⚠️ 使用约定（重要）：
//   1. states: 是「一次性 Future」语义，适合开页拉一次的页面。
//      Provider / ChangeNotifier 驱动的响应式页面请勿使用 states:
//      改为在 body 里手动判断 provider.loading / provider.error，
//      直接渲染 AppLoading / AppError / AppEmpty（见 storage_page.dart 范例）。
//   2. 需要重新加载时，改变 AppPageStates.reloadKey 即可触发，
//      父级单纯重建不会重复拉取。
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
///
/// 仅在「一次性 Future」场景使用，且默认只在首次挂载时加载一次。
/// 需要重新加载时，请改变 [reloadKey]（推荐）或调用 [onRetry]。
class AppPageStates<T> {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) buildData;
  final bool Function(T data)? emptyWhen;
  final String emptyMessage;
  final String? emptyHint;
  final Future<void> Function()? onRetry;
  final String? loadingMessage;

  /// 重新加载的「钥匙」：值发生变化才触发一次新的 load。
  ///
  /// - 为 null（默认）：只在首次挂载时加载一次，父级重建不会重复拉取。
  /// - 非 null：当新旧 [reloadKey] 不相等时触发重新加载（例如筛选条件变化）。
  ///
  /// 之所以不用「比较 config 对象引用」来决定是否重载，是因为父级 build
  /// 每次都会 new 一个 AppPageStates，引用永不相等，会导致父级每次重建
  /// 都重新拉取 Future（在 Provider 响应式页面里会形成重建→refetch 循环）。
  final Object? reloadKey;

  const AppPageStates({
    required this.load,
    required this.buildData,
    this.emptyWhen,
    this.emptyMessage = '暂无内容',
    this.emptyHint,
    this.onRetry,
    this.loadingMessage,
    this.reloadKey,
  });
}

/// ⚠️ `states:` 是泛型参数 [T] 的唯一来源。
///
/// 之所以让 AppPage 泛型化：若不泛型，`states` 的静态类型只能是
/// `AppPageStates<dynamic>`，而 `AppPageStates<String>.buildData` 的运行时类型是
/// `(BuildContext, String) => Widget`；引擎读取该字段时会插入一次隐式转型检查，
/// 在运行期抛出 `_TypeError: type '(BuildContext, String) => Text' is not a
/// subtype of type '(BuildContext, dynamic) => Widget'`。
/// 泛型化后 `buildData` 全程保持 `T`，无需任何 `as dynamic` 绕过。
/// 不使用 `states:` 的页面无需改动（T 会被推断为 `dynamic`）。
class AppPage<T> extends StatefulWidget {
  final String title;

  /// 自定义标题组件（可选）。
  ///
  /// `title` 只能是纯文本，而部分页面（如 provider_detail_page）的标题是
  /// 「品牌头像 + 动态名称」的富标题。传入 [titleWidget] 时完全覆盖
  /// `Text(title)` 的渲染；未传则回落到纯文本标题，两者互不干扰。
  final Widget? titleWidget;
  final Widget? body;
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
  final AppPageStates<T>? states;

  /// 自定义底部槽位
  final Widget? bottom;

  const AppPage({
    super.key,
    required this.title,
    this.titleWidget,
    this.body,
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
  State<AppPage<T>> createState() => _AppPageState<T>();
}

class _AppPageState<T> extends State<AppPage<T>> {
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
                  haptics: true,
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
      content = _StatesScope<T>(config: widget.states!, child: content);
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
        title: widget.titleWidget ?? Text(widget.title),
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
    if (segs == null) return widget.body ?? const SizedBox.shrink();

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
class _StatesScope<T> extends StatefulWidget {
  final AppPageStates<T> config;
  final Widget? child;
  const _StatesScope({required this.config, this.child});

  @override
  State<_StatesScope<T>> createState() => _StatesScopeState<T>();
}

class _StatesScopeState<T> extends State<_StatesScope<T>> {
  Future<T>? _future;

  /// 当前已加载的 reloadKey，用于判断是否真的需要重新拉取
  Object? _loadedReloadKey;

  Future<T> _fetch() {
    _loadedReloadKey = widget.config.reloadKey;
    final Future<T> f = widget.config.load();
    // ⚠️ 必须立刻挂一个「只吞错误」的监听。
    // 重试场景下 setState 要下一帧才重建，FutureBuilder 那时才订阅；
    // 而 future 可能已经以错误完成，会被判定为「未处理的异步异常」上报
    // （测试里直接判失败，真机上走 FlutterError.onError 产生噪声日志）。
    // 挂了这个监听后，后续 FutureBuilder 仍能正常拿到 snapshot.hasError。
    f.ignore();
    return f;
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(_StatesScope<T> old) {
    super.didUpdateWidget(old);
    // ✅ 修复：只按 reloadKey 判断是否重载，不再按 config 对象引用比较。
    // 旧实现中父级 build 每次 new 一个 AppPageStates，引用永远不等，
    // 导致父级每次重建都重新拉取 Future（Provider 页面会重建→refetch 循环）。
    final nextKey = widget.config.reloadKey;
    if (nextKey != null && nextKey != _loadedReloadKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // ⚠️ 不能写成 setState(() => _future = _fetch())：赋值表达式的值就是
        // 那个 Future，setState 会断言「回调返回了 Future」。
        final next = _fetch();
        setState(() {
          _future = next;
        });
      });
    }
  }

  void _retry() {
    // 同上：先取 Future，再同步 setState。原实现 `setState(() => _future = _fetch())`
    // 在点「重试」时会触发 Flutter 断言失败。
    final next = _fetch();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return FutureBuilder<T>(
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
        return cfg.buildData(context, data as T);
      },
    );
  }
}
