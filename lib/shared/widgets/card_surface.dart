import 'package:flutter/material.dart';

/// 页面级统一卡片规范：
/// - 背景：浅色近白、深色半透明白（与现有 iOS 分组卡片一致）
/// - 描边：细黑边——浅色下用低透明度黑，深色下用低透明度白，宽度 0.8
///
/// 设计页与所有设置子页面的卡片统一使用本工具，保证视觉一致。
class AppCardSurface {
  AppCardSurface._();

  /// 卡片背景色。
  static Color background(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? Colors.white10
        : Colors.white.withOpacity(0.96);
  }

  /// 统一细黑边描边。
  static Border border(BuildContext context, {double width = 0.8}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Border.all(
      color: isDark
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.10),
      width: width,
    );
  }
}