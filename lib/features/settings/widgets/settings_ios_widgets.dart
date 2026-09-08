// ──────────────────────────────────────────────────────────────
// settings 系 iOS 分组组件 —— **已上提到 shared**
//
// 批次 4 时发现 `backup` / `provider` 两个 feature 也各有一份逐值相同的
// `_iosSectionCard` / `_iosDivider` / `_iosNavRow` 副本，而它们不该反向依赖
// `features/settings`。故这三个组件上提到
// `lib/shared/widgets/app_section.dart`（迁移计划「待办 F」）。
//
// 本文件保留为**类型别名 + 再导出**，让已迁移的 6 个 settings 页面
// （about / sponsor / theme_settings / default_model / display_settings /
// tts_services）无需改动一行代码即可继续工作。
//
// 新页面请直接使用 `AppSectionCard` / `AppSectionDivider` / `AppNavRow` /
// `AppSwitchRow`。
//
// ⚠️ 经验 #38：Dart 的 `export` **不会**把名字引入本库自身的作用域——它只影响
// 「别的库 import 本库时能看到什么」。所以 shim 里既有 typedef 引用共享类，
// 就必须 `import` + `export` **成对出现**，否则所有 typedef 全报
// `undefined_class`，连带 6 个使用方页面报 `creation_with_non_type` /
// `invocation_of_non_function`。
// ──────────────────────────────────────────────────────────────

import '../../../shared/widgets/app_section.dart'
    show AppSectionCard, AppSectionDivider, AppNavRow, AppSwitchRow;
export '../../../shared/widgets/app_section.dart'
    show AppSectionCard, AppSectionDivider, AppNavRow, AppSwitchRow;

/// 兼容别名：`AppSectionCard` 的旧名（见文件头注释）。
typedef SettingsSectionCard = AppSectionCard;

/// 兼容别名：`AppSectionDivider` 的旧名。
typedef SettingsDivider = AppSectionDivider;

/// 兼容别名：`AppNavRow` 的旧名。
typedef SettingsNavRow = AppNavRow;

/// 兼容别名：`AppSwitchRow` 的旧名（原「待办 E」，`display_settings` 等页面的
/// 私有 `_iosSwitchRow` 尚未切换，先留别名）。
typedef SettingsSwitchRow = AppSwitchRow;
