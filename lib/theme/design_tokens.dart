import 'package:flutter/material.dart';

// ──────────────────────────────────────────────────────────────
// Design Tokens — 应用全局设计常量
// 语义化命名，避免页面里到处写 magic number
// ──────────────────────────────────────────────────────────────

/// 间距 / 留白体系（对应 Material 3 spacing scale）
class AppGap {
  static const double xxxs = 2;
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // 兼容旧名（逐步废弃）
  static const double none = xxxs;   // 2
  static const double defaultSm = sm;
  static const double defaultMd = md;
}

/// 圆角体系（对应 Material 3 shape scale）
class AppRadius {
  static const double none = 0;
  static const double tiny = 2;    // chip 内部、badge
  static const double xs = 4;      // 小控件、分割线容器
  static const double sm = 8;      // 小卡片、text field
  static const double md = 12;     // 标准卡片
  static const double lg = 16;     // 大卡片、弹窗
  static const double xl = 20;     // 大容器
  static const double capsule = 28; // FAB、pill-shaped button
  static const double circular = 999; // 圆形

  // 兼容旧名
  static const double defaultMd = md;
}

// 兼容旧类名（AppSpacing 已废弃，用 AppGap）
@Deprecated('Use AppGap instead')
class AppSpacing {
  // 镜像 AppGap 的值，保持旧代码能编译
  static const double xxxs = AppGap.xxxs;
  static const double xxs = AppGap.xxs;
  static const double xs = AppGap.xs;
  static const double sm = AppGap.sm;
  static const double md = AppGap.md;
  static const double lg = AppGap.lg;
  static const double xl = AppGap.xl;
  static const double xxl = AppGap.xxl;
  static const double xxxl = AppGap.xxxl;
}

// 兼容旧类名（AppRadii 已废弃，用 AppRadius）
@Deprecated('Use AppRadius instead')
class AppRadii {
  static const double none = AppRadius.none;
  static const double tiny = AppRadius.tiny;
  static const double xs = AppRadius.xs;
  static const double sm = AppRadius.sm;
  static const double md = AppRadius.md;
  static const double lg = AppRadius.lg;
  static const double xl = AppRadius.xl;
  static const double capsule = AppRadius.capsule;
  static const double circular = AppRadius.circular;
}

/// 页面级 padding 预设
class AppPagePadding {
  /// 水平 16 —— 列表/卡片类页面 body padding
  static const EdgeInsets h = EdgeInsets.symmetric(horizontal: AppGap.md);

  /// 水平 16 + 垂直 12 —— 最常用的页面 body padding
  static const EdgeInsets hv = EdgeInsets.symmetric(horizontal: AppGap.md, vertical: AppGap.sm);

  /// 水平 16 + 垂直 16
  static const EdgeInsets all = EdgeInsets.all(AppGap.md);

  /// 水平 0 —— 全屏沉浸式页面（聊天、视频）
  static const EdgeInsets zero = EdgeInsets.zero;

  /// Scaffold body 标准 padding（顶栏下方的内容区）
  static const EdgeInsets content = EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md);
}

/// 语义化颜色常量（对 Theme.of(context).colorScheme 的补充）
class AppColors {
  static const Color textMuted = Colors.black54;

  /// divider / 细分割线
  static const Color dividerLight = Color(0x1F000000);
  static const Color dividerDark = Color(0x29FFFFFF);

  /// success / warning / error 背景透明度（配合 colorScheme.errorContainer 使用）
  static const double containerAlphaSoft = 0.30;
  static const double containerAlphaMedium = 0.50;
}

/// 阴影层级
class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> medium = [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> lift = [
    BoxShadow(
      color: Colors.black.withOpacity(0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// 文字语义样式（从 Theme.of(context).textTheme 派生）
/// 避免在页面里写 Theme.of(context).textTheme.headlineMedium!.copyWith(...)
class AppText {
  static TextStyle h1(TextTheme t) => t.headlineMedium!.copyWith(fontWeight: FontWeight.w600);
  static TextStyle h2(TextTheme t) => t.titleLarge!.copyWith(fontWeight: FontWeight.w600);
  static TextStyle h3(TextTheme t) => t.titleMedium!.copyWith(fontWeight: FontWeight.w600);
  static TextStyle body(TextTheme t) => t.bodyMedium!;
  static TextStyle bodyStrong(TextTheme t) => t.bodyMedium!.copyWith(fontWeight: FontWeight.w500);
  static TextStyle caption(TextTheme t) => t.bodySmall!;

  static TextStyle muted(TextTheme t, ColorScheme cs) =>
      t.bodyMedium!.copyWith(color: cs.onSurface.withOpacity(0.6));

  static TextStyle hint(TextTheme t, ColorScheme cs) =>
      t.bodySmall!.copyWith(color: cs.onSurface.withOpacity(0.5));
}

/// AppBar 高度（Fluent/Apple 风格顶栏）
class AppAppBar {
  static const double height = kToolbarHeight;          // 56
  static const double expandedHeight = 120;             // 可折叠顶栏
}
