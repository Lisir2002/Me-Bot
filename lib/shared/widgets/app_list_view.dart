import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// 页面级统一滚动列表。
///
/// 来历：全仓 30+ 页面在 `AppPage(scrollable: false)` 模式下各自手写
/// `ListView(padding: EdgeInsets.fromLTRB(16, ...))`，水平 padding 基本都是
/// 16，但垂直值从 8 到 32 五花八门；更严重的是经常漏配 `AppPage.bodyPadding:
/// zero`，导致「AppPage 默认 16 + ListView 自带 16」双层叠加，卡片视觉过窄
/// （见 security_page 修复记录）。
///
/// 本组件把「水平 16 + 合理垂直默认值」固化，页面只需传 children：
///
/// ```dart
/// AppPage.selfScrolling(
///   title: '安全',
///   body: AppListView(
///     children: [_section1(), _section2()],
///   ),
/// )
/// ```
///
/// 垂直 padding 默认 `top: 12 / bottom: 16`（与 `AppPagePadding.content` 一致），
/// 需要更多底部留白（如底部有悬浮按钮）时传 [bottomPadding] 覆盖。
class AppListView extends StatelessWidget {
  const AppListView({
    super.key,
    required this.children,
    this.topPadding = AppGap.sm,
    this.bottomPadding = AppGap.md,
    this.physics,
    this.controller,
    this.shrinkWrap = false,
    this.cacheExtent,
  });

  /// 列表内容。
  final List<Widget> children;

  /// 顶部内边距。默认 12，与 `AppPagePadding.content` 对齐。
  final double topPadding;

  /// 底部内边距。默认 16；页面底部有悬浮按钮/FAB 时调大。
  final double bottomPadding;

  final ScrollPhysics? physics;
  final ScrollController? controller;
  final bool shrinkWrap;
  final double? cacheExtent;

  /// 水平 padding 固定为 16——这是设计系统的卡片边距，不允许页面覆盖。
  static const double _horizontal = AppGap.md;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      cacheExtent: cacheExtent,
      padding: EdgeInsets.fromLTRB(
        _horizontal,
        topPadding,
        _horizontal,
        bottomPadding,
      ),
      children: children,
    );
  }
}

/// [AppListView] 的 builder 版本（长列表用，避免一次性构建所有子项）。
class AppListViewBuilder extends StatelessWidget {
  const AppListViewBuilder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.topPadding = AppGap.sm,
    this.bottomPadding = AppGap.md,
    this.physics,
    this.controller,
    this.cacheExtent,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double topPadding;
  final double bottomPadding;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final double? cacheExtent;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      physics: physics,
      cacheExtent: cacheExtent,
      padding: EdgeInsets.fromLTRB(
        AppGap.md,
        topPadding,
        AppGap.md,
        bottomPadding,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
