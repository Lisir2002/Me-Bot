# UI 骨架迁移计划 — AppPage / AppSheet / AppStates

> 目标：把项目里手写 `Scaffold + AppBar + body padding` 的页面逐步迁移到
> [AppPage 骨架引擎](../../lib/shared/widgets/app_page.dart)，统一骨架、三态、分段、弹层。
>
> 本计划让每次迁移都有"入口 → 改动 → 验证"的明确路径，可逐条打勾。

---

## 〇、变更记录（实时更新）

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-07 | **引擎修复（P0）** | `app_page.dart`：`AppPageStates` 新增 `reloadKey`；`_StatesScopeState.didUpdateWidget` 改为**按 `reloadKey` 判断重载**，不再按 config 对象引用比较。修复"父级每次重建都重新拉取 Future"的隐患（Provider 响应式页面会形成重建→refetch 循环）。 |
| 2026-09-07 | **引擎约定补充** | 文件头新增使用约定：`states:` 仅用于「一次性 Future」；Provider 驱动页面请在 body 内手动渲染 `AppLoading`/`AppError`/`AppEmpty`。 |
| 2026-09-07 | ✅ 批次 1 首个页面完成 | `provider/pages/provider_network_page.dart` 迁移完成（见第四节勾选）。 |
| 2026-09-07 | ✅ **回归基线建立** | 新增 `test/app_page_test.dart`（12 个 widget 用例），覆盖槽位/分段/三态/滚动，并锁定 reloadKey 重载策略。引擎改动须先跑通此测试。 |
| 2026-09-07 | ✅ **批次 1 全部完成（6/6）** | 完成 `select_copy` / `terminal_placeholder` / `message_edit` / `google_fonts_picker` / `more`（含上一条 `provider_network`）。 |
| 2026-09-07 | 🔄 **批次 2 启动（4/13）** | 完成 `mcp_server_detail`（**segments top 样板**）/ `tags_manager` / `chat_history` / `sponsor`。 |
| 2026-09-07 | 🔄 **批次 2（9/13）** | 完成 `storage_log` / `storage_cache` / `storage_detail` / `storage_media`（**首个真正用上 `bottom:` 槽位的页面**）/ `mcp`（**AppSheet 收敛 + 私有按钮删除**）。 |
| 2026-09-07 | ⚠️ **踩坑修正：Column 宽度** | AppPage 滚动容器给子项**紧宽度**，但 `Column` 默认 `crossAxisAlignment: center` 会把子项宽度放宽 → 卡片缩成内容宽度。所有 `body: Column(...)` 必须 `crossAxisAlignment: CrossAxisAlignment.stretch`。已补修 `storage_log/cache/detail`。 |
| 2026-09-07 | ⚠️ **踩坑修正：AppGap.sm/md** | 复核 `design_tokens.dart`：`sm = 12`、`md = 16`。此前多处把原 12px 写成 `AppGap.md`（+4px 偏移），已全量 sed 修正并复核。 |
| 2026-09-07 | ✅ **批次 2 全部完成（13/13）** | 收官 4 页：`network_proxy`（手写 sheet → `AppSheet`）/ `quick_phrases`（`ReorderableListView` + 复杂弹层只收敛外层调用）/ `theme_settings`（清理重复 import）/ `translate`（**第二个 `bottom:` 槽位样板**）。 |
| 2026-09-07 | ✅ **收尾代办 A：提取 `StorageInfoHeader`** | 新增 `lib/features/storage/widgets/storage_info_header.dart`，合并 4 个 storage 子页逐字重复的私有 `_InfoHeader`（角标差异用 `StorageInfoNoteStyle.caution/cleanable` 表达）。放在 **features 层**而非 shared——它依赖 storage 私有的 `storageFormatBytes`/`storageCardBorder`。 |
| 2026-09-07 | ✅ **收尾代办 B：新增共享按压原语** | `ios_tactile.dart` **纯增量**新增 `IosTactileRow`（回传 pressed / 可选缩放 / releaseDelay / 触觉受设置约束）与 `IosPressColor`（文字色按压过渡）。现有 `IosIconButton`/`IosCardPress` 一字未动。`mcp` / `theme_settings` / `sponsor` / `quick_phrases` 四页的私有 `_TactileRow`/`_TactileCard`/`_AnimatedPressColor` 全部删除收敛。 |
| 2026-09-07 | 🔄 **批次 3 启动（1/8）** | `about_page`（814 行）完成：骨架 + 双私有触觉副本收敛；彩蛋弹层按 AppSheet 边界规则**保持自建**；`_iosNavRow*` 留待与 `sponsor`/`tts`/`display` 一起提取 `SettingsNavRow`。 |
| 2026-09-07 | 🔄 **批次 3（2/8）** | `local_snapshot_page`（727 行）完成：骨架 + 三态走手动分支 + `Column(stretch)`；私有 `_ActionChip` 的 `GestureDetector+AnimatedScale+Haptics` 三件套 → `IosTactileRow`（−50 行）；顺带修「首帧闪空态」（`_loading` 初值改 `true`）。 |
| 2026-09-07 | 🔄 **批次 3（3/8）** | `default_model_page`（574 行）完成：骨架 + `Column(stretch)`；两个逐字重复的底部弹层 → 参数化 `_showPromptSheet` + **`AppSheet` 完整承载**（title/footer/内置把手）；私有 `_TactileIconButton`/`_TactileRow` → 共享原语；清 8 处死代码/重复 import。**574 → 403 行（−171）**。 |
| 2026-09-07 | ⚠️ **引擎能力缺口登记** | `IosIconButton` **不带触觉反馈**，而项目里各页私有 `_TactileIconButton` 普遍调 `Haptics.light()`。直接替换会静默丢掉返回键/卡内设置键的触觉。本页用局部包装 `_navIcon` 兜住（`TODO(引擎)` 已写在源码里）。建议后续给 `IosIconButton` 加 `haptics` 参数（默认值取 `false` 以保持兼容）。**已迁移的 `about_page` / `mcp_page` 也适用这条，需一并回看。** |
| 2026-09-07 | ✅ **收尾代办 C：引擎补 `IosIconButton.haptics`（已落地）** | `ios_tactile.dart` 纯增量加 `bool haptics = false`，`onTap`/`onLongPress` 按需 `Haptics.light()`（与原私有实现一致，不受设置开关约束，对齐 `StorageTactileIconButton`）。**共补 17 处调用点**：引擎默认返回键 1 + `about` 1 / `translate` 5 / `quick_phrases` 2 / `theme_settings` 1 / `network_proxy` 1 / `sponsor` 1 / `tags_manager` 2 / `mcp` 3。**`default_model` 的局部 `_navIcon` 包装随之删除**。 |
| 2026-09-07 | 🔄 **批次 3（4/8）** | `assistant_settings_page`（627 行）完成：`ReorderableListView` → **`scrollable: false`**（checklist 3c）；新增助手弹层 → `showAppSheet`（保留居中标题故内容自建）；`_TactileCard` → `IosCardPress`；`_IosOutline/FilledButton` → `IosTactileRow`；删死代码 `_initials`。**627 → 549 行**。 |
| 2026-09-07 | ✅ **收尾代办 D：提取 `SettingsNavRow` 系（已落地）** | 新增 `lib/features/settings/widgets/settings_ios_widgets.dart`：`SettingsSectionCard` / `SettingsDivider` / `SettingsNavRow`。合并 `about` / `sponsor` / `theme_settings` 的逐字重复私有副本（`default_model` 那份是死代码，已删）。差异用参数表达（见批次 3 经验 #11）。**about 718→556、sponsor 335→250、theme 218→194，净 −86 行**。`tts_services` / `display_settings` 迁移时直接用。 |
| 2026-09-07 | 🔄 **批次 3（5/8）** | `tts_services_page`（954 行）完成：骨架 + `Column(stretch)`；5 个私有 helper 收敛（`_TactileIconButton`/`_TactileRow`/`_AnimatedPressColor`/`_iosSectionCard`/`_iosDivider`）；**4 个弹层**——错误详情、系统 TTS 配置 → `AppSheet` 完整承载，新增·编辑表单 → `showAppSheet`（左关|中题|右确认三段式头），选项选择 → `showAppSheet`（原手写 `showModalBottomSheet`）。原 `(ctx as Element).markNeedsBuild()` 改用 `StatefulBuilder` 的 `setState`。 |
| 2026-09-07 | ⚠️ **`_SmallTactileIcon` 保留私有（有意）** | 它的视觉语义与 `IosIconButton` 不同：启用 0.9 / 按压 0.6 / 禁用 0.3 的**透明度阶梯**，且按压无底色变化。`IosIconButton` 是「向白/黑混合 + 按压底色」，硬套会改观感。私有 ≠ 冗余：视觉语义不同的组件不该硬并。 |
| 2026-09-07 | ⚠️ **修正：`SettingsNavRow.haptics` 默认值** | 我最初把共享组件里的 `haptics` 写死 `false`（照抄 `about`/`sponsor`）。复核仓库原文：`theme_settings`/`default_model`/`display_settings` 的私有副本是 `true`，`about`/`sponsor` 才显式 `false`。**已改默认为 `true`**，并给 `about`（7 处）/`sponsor`（2 处）补回 `haptics: false`。这是我自己引入的回归，共影响 2 个已交付文件。 |
| 2026-09-07 | 🔧 **验证环境打通（重要）** | 沙箱网络恢复：`git clone` 拿到全量源码；下载 **Flutter 3.47.2 / Dart 3.13.2**（原 SDK 是 3.0.0/2.17，无法解析项目 record 语法）。后续所有交付文件改为**先真编译校验**再交付，不再只靠括号平衡脚本。（`flutter.version.json` 里 `frameworkVersion` 需手动改成 `3.47.2`，否则 pub 拒绝解析依赖） |
| 2026-09-07 | 🐞 **引擎 3 个真 bug（靠跑测试才发现）** | 打通验证环境后首跑 `flutter test`，13 个用例**失败 6 个**，全部指向引擎而非页面：① `AppPageStates<T>` 用具体类型即运行期 `_TypeError` → `AppPage<T>` 泛型化；② `setState(() => _future = _fetch())` 返回 Future 触发断言，**点「重试」就抛** → 改块体；③ 重试时 future 的 error 被当成未处理异步异常 → `_fetch()` 加 `f.ignore()`。修完 **13/13 全绿**。详见批次 3 经验 #24/#25/#26。 |
| 2026-09-07 | 🔄 **批次 3（6/8）** | `display_settings_page`（1086 行）完成：主页面 + **4 个子页面**（聊天项显示/渲染/行为启动/触觉）全部换成 `AppPage` 槽位；13 行 `_iosNavRow` → `SettingsNavRow`、`_iosSectionCard`/`_iosDivider` → `SettingsSectionCard`/`SettingsDivider`；**4 个选项弹层 → 泛型 `_OptionSheet<T>`**（`showAppSheet(isScrollControlled: false)`）；**3 个滑杆弹层 → `showAppSheet` + `_sliderTheme`/`_sliderThumb`**；删私有 `_TactileRow`/`_TactileIconButton`/`_AnimatedPressColor`/`_sheetDivider` 与未用的 `header()`。**1086 → 904 行**，`showModalBottomSheet` 归零。 |
| 2026-09-07 | 🔄 **批次 3（7/8）** | `multi_key_manager_page`（1025 行）完成：骨架 + `Column(stretch)` + `bodyPadding fromLTRB(md, sm, md, md)`；AppBar 3 个动作与每个 key 的编辑/删除键 → `IosIconButton(haptics:true, size:22, minSize:44)`；策略行 → `IosTactileRow` + `IosPressColor`（`pressedScale` 不传 = 不缩放，对上原来的 1.00）；**策略弹层 → `AppSheet` 完整承载**（与经验 #19 的「无把手自建」不同，这个弹层**本来就有把手**，正好吃得下）；添加/编辑两个表单弹层 → `showAppSheet` + 共用 `_formSheetHeader`（把手 + 左关|中题）/ `_formField`（3 个字段形状一致）。删 3 处死代码（`_TactileScale`/`_divider`/`_chooseDetectModel`）、2 个重复 import、1 个无引用 import（`flutter/cupertino.dart`）。**1025 → 802 行**。本页静态检查命中从 **25 条归零**（含 2 条 `duplicate_import`）。 |
| 2026-09-07 | 🧹 **顺手清 lint：`sort_child_properties_last` ×4** | `AppSheet` 的语义顺序是 title → children → footer，与 lint 要求的「children 放最后」冲突。`mcp_page`(1) / `default_model`(1) / `tts_services`(2) 共 4 处用 `// ignore:` 显式抑制（项目里已有 13 处 `// ignore:` 先例），不改参数顺序以免伤害可读性。修复后 analyze 总数 **3124 → 3120**。 |
| 2026-09-07 | ✅ **批次 3（8/8）收官** | `providers_page`（1123 行）完成：骨架 + **`safeArea: false`**（本页自己按 `MediaQuery.padding.bottom` 留系统栏）+ **`scrollable: false`**（`ReorderableListView` 自带滚动）+ **`bodyPadding: zero`**（列表自带 padding）；底部选择栏是滑入浮层，**坚持 `Stack + Positioned` 而非 `bottom:` 槽位**；多选导出弹层 → `showAppSheet`；4 个 AppBar 动作 → `IosIconButton`；`_TactileRow`/`_AnimatedPressColor` → 共享原语。删 5 处死代码（`_items` / `_CapsuleButton` 65 行 / `_Pill` / `_DragHandle` / `_tintPurpleSilicon` / `isFirst`）+ 1 个重复 import。**1123 → 941 行**。`flutter analyze` 全仓 **3278 → 3102（净 −176）**，骨架测试 **13/13 全绿**。 |
| 2026-09-07 | 📌 **新增待办 F：`_iosSectionCard` 全仓 12 份** | `multi_key_manager` 迁移时统计：全仓有 **12 个文件**各持一份 `_iosSectionCard`（assistant/backup/model/provider×2/search/settings×6）。现已存在三份同形不同名的共享实现（`SettingsSectionCard` / `StorageSectionCard` / 本页改用 `AppCardSurface` 的本地版）。provider 页不便反向依赖 `features/settings`，故本页先本地保留。**批次 3 收官后统一提取 `shared/widgets/app_section_card.dart`**。 |
| 2026-09-07 | 🔄 **批次 4（1/4）** | `usage_stats_page`（1297 行）完成：**全仓第一个真正用上 `states:` 槽位的生产页面**——整页就是一个 `loadStatsData` Future，手写 `FutureBuilder` 三态整套删掉；刷新按钮 `setState(() => _future = ...)` → `reloadKey: _reloadToken`（自增即重载）；`UsageStatsBody` 自带 ListView(padding 16) → `scrollable: false` + `bodyPadding: zero`；`IconButton` → `IosIconButton(haptics:true, minSize:44)`。**单文件 analyze 0 issues**；`DesktopStatsPane` 无 Scaffold（桌面内嵌面板），不在迁移范围内。 |
| 2026-09-07 | ✅ **待办 F + 待办 E 一并落地：`shared/widgets/app_section.dart`** | 新增 `AppSectionCard` / `AppSectionDivider` / `AppNavRow`（待办 F）与 **`AppSwitchRow`（待办 E，8 份 `_iosSwitchRow`）**，四个都放 shared。`settings_ios_widgets.dart` 改为 **typedef + import/export 兼容 shim**，已迁移的 6 个 settings 页面零改动。`backup_page` 成为 shared 版首个消费者。 |
| 🚨 2026-09-08 | 🐞 **真 bug（上一轮引入，本轮 analyze 全量才暴露）：shim 只有 `export`** | Dart 的 `export` **不会把名字引入本库自身作用域**（它只决定「别的库 import 本库能看到什么」）。`settings_ios_widgets.dart` 里 `typedef SettingsSectionCard = AppSectionCard;` 因此全部 `undefined_class`，连带 6 个使用方页面报 `creation_with_non_type` / `invocation_of_non_function`，**error 数 0 → 78**。修复：`import` + `export` **成对出现**（经验 #38）。教训：**shim/桶文件必须配 import；每轮改完要跑一次全量 analyze，不能只看单文件**。 |
| 2026-09-08 | 🔄 **批次 4（2/4）** | `backup_page`（1405 行）完成：骨架 + `Column(stretch)` + `bodyPadding fromLTRB(md, sm, md, xl)`；`_iosSectionCard`/`_iosDivider`/`_iosNavRow`/`_iosSwitchRow` 4 份私有副本全删 → shared；`_TactileRow`/`_AnimatedPressColor`/`_TactileIconButton`/`_TactileTextButton` → `IosTactileRow`/`IosPressColor`/`IosIconButton(haptics:true)`；3 个手写弹层 → `showAppSheet`/`AppSheet`（**居中标题/三段式头走「`title` 留空 + 首个 child 自绘」**，见经验 #39）；`_RemoteListSheet` 的 `DraggableScrollableSheet` 超出模板能力，只换外层并**删掉内层重复的 `SafeArea`**。**1405 → 1122 行**，净新增 issues **1 → 0**（补 `// ignore: sort_child_properties_last`）；全仓 **3278 → 3095（净 −183）**；测试 18 过 / 1 败（同基线）。 |
| 2026-09-08 | 🔄 **批次 4（3/4）** | `search_services_page`（1533 行）完成：骨架 + `Column(stretch)` + `backgroundColor: cs.surface` 透传；`_iosSectionCard`/`_iosDivider`/`_TactileRow`/`_AnimatedPressColor`/`_TactileIconButton` → shared/共享原语；服务行**外层 tap + 内层 longPress 两层手势合并**到 `IosTactileRow(onTap, onLongPress)`（行为等价，触觉保持 false）；编辑弹层 → `showAppSheet`（`_EditServiceSheet` 不再自带 SafeArea/viewInsets Padding）；操作表 → `showAppSheet(isScrollControlled: false)`（**显式传 false**，经验 #20）；**`_addService` 弹层保留手写**（需要 `constraints: maxHeight(0.85h)`，showAppSheet 不支持，且内容是 AnimatedSize+AnimatedSwitcher+Flexible，套 AppSheet 会双重滚动）；静态选项行展开（`_TactileRow(onTap:null)` 是死分支）。清死代码 9 处（`_selectService` / `selected` / `_getServiceIcon` / `_getServiceStatus` / `isDark` / `_brandBadgeForName`+ignore / 4 处无效 `!` / 2 重复 import / 2 处局部 `_buildTextField` 改名）。**1533 → 1377 行；自身 46 条（14 warning）→ 26 条（0 warning）**；全仓 **3278 → 3075（净 −203）**；测试 13/13。 |
| 2026-09-08 | ✅ **引擎扩展：`AppPage.titleWidget`（纯增量）** | `title` 是 `String` 渲染为 `Text(title)`，表达不了 `provider_detail_page` 的富标题（品牌头像 `_BrandAvatar` + 动态名称）。新增 `final Widget? titleWidget;`，AppBar 渲染 `widget.titleWidget ?? Text(widget.title)`——未传完全走老路，**零破坏**。`test/app_page_test.dart` 补第 14 个用例：传入时覆盖纯文本、未传时回落 `Text(title)`。 |
| 2026-09-08 | ✅ **批次 4 全部完成（4/4 · 全项目 34/34 页收官）** | `provider_detail_page`（2412 行，全仓最大页）完成：骨架 + **`titleWidget` 富标题**（首个使用者）；`PageView` + 自绘 iOS 胶囊 `_BottomTabs` → `scrollable:false` + `bodyPadding: zero` + **`bottom:` 槽位**（**弃用 segments bottom**：引擎该模式渲染 Material `NavigationBar` 且 body 无滑动，会丢掉 PageView 手势与胶囊视觉，见经验 #42）；4 个 AppBar 按钮 → `IosIconButton`（原按钮点按**无**触觉 → `haptics` 保持默认 false；`pressedColor` 保真原 0.7 透明度按压色）；`_TactileRow`/`_TactileIconButton` 私有类删除 → `IosTactileRow`+`IosPressColor`（5 处手写 `TweenAnimationBuilder` 按压色一并收敛）；类型选择弹层 → `AppSheet`；模型选择弹层 → `showAppSheet` 外壳 + 内层 `DraggableScrollableSheet` 保留（删内层重复 SafeArea/AnimatedPadding）；死代码 ×3（`_switchRow`/`_checkboxRow`/`_buildProviderTypeSelector` 全仓零引用）+ `_preferMonochromeWhite` + 2 重复 import；`_iosSectionCard` **保留私有**（背景公式 `lerp(surface→white, 6%/92%)` 与共享版不同，见经验 #43）。**2412 → 2116 行（−296）**；自身 analyze **净新增 0**；全仓 **3278 → 3062（净 −216）**；`app_page_test` **14/14**、全量测试 19 过 / 1 败（`widget_test.dart` 模板，同基线）。踩坑见经验 #40。 |
| 2026-09-08 | 🚀 **v0.0.38 发版（Android）** | 代码与文档随 main 推送（`8f640a0`），tag `v0.0.38`；复用仓库既有 `build-stable.yml` 由 GitHub Actions 构建（run `34179006252`）：`flutter build apk --release --obfuscate --split-debug-info`（arm64+x64），产物 `MiniMeCore_android_0.0.38+38_universal.apk`（86.22 MB）已挂 [Release](https://github.com/Lisir2002/Me-Bot/releases/tag/v0.0.38)。其余平台按约定后续再发。 |

### 批次 2 新增经验（重要）

| # | 经验 | 结论 |
|---|------|------|
| 1 | **`states:` 只适用于「整页就是一个 Future」**。`sponsor_page` 的 Future 只负责页面下半部分，用 `states:` 会吞掉上半部分卡片 | 局部 Future 一律用手动 `AppLoading`/`AppEmpty`/`AppError` |
| 2 | **分段（segments）模式下引擎不加 padding、不包滚动**，`mcp_server_detail` 的每个 Tab body 必须自带 ListView + padding | 已在该页注释中标明，作为 segments 范式 |
| 3 | **`ReorderableListView` 也是自带滚动**，`tags_manager` 同样必须 `scrollable:false` | 见 3c |
| 4 | **`IosIconButton` 已确认支持 `color`/`size`/`minSize`/`semanticLabel`**，可安全替换页面私有 `_TactileIconButton` | `sponsor_page` 首个落地，删除其私有副本 |
| 5 | **原无 SafeArea 的页面迁移后会多出安全区内边距**（如 `chat_history`） | 属预期统一行为；要完全还原加 `safeArea: false` |
| 6 | **`bottom:` 槽位不进 SafeArea**：AppPage 只对 body 套 SafeArea，`bottomNavigationBar` 在外层。底部操作条需自包 `SafeArea(top: false)` | `storage_media` 首个落地（顺带修了原实现在 iOS home indicator 下删除键被压住的问题） |
| 7 | **引擎的 `scrollable: true` 是 `ListView(children:[body])`，给子项无界高度 + 紧宽度**。需要撑满剩余高度的页面必须 `scrollable: false`（如 `storage_media` 的网格列表） | 见 3c；同时引出 3d |
| 8 | **`AppSheet` 可承载底部双按钮**（`footer:` 参数），简单错误详情/确认类弹层均可收敛 | `mcp_page` 的错误详情弹层已从手写 `showModalBottomSheet` 改为 `AppSheet` |
| 9 | ~~`_TactileRow` 暂无共享等价物~~ **已解决**：`ios_tactile.dart` 新增 `IosTactileRow` + `IosPressColor` 原语。未按原设想改 `IosCardPress`——它的按压效果是「固定向白/黑混合的底色」，表达不了 `theme_settings` 的「透明底 + 文字变色」，硬套会引入视觉变化 | 新原语是**纯增量**，不动现有类；`mcp`/`theme_settings`/`sponsor`/`quick_phrases` 已收敛，行为差异仅一处：`quick_phrases` 卡片触觉由「无条件」改为受 设置→列表项触觉 开关约束（视为修正） |
| 10 | **`bottom:` 槽位在 SafeArea 之外**。原实现若把底部条放在 body 的 SafeArea 内（`translate` 就是），迁移后底栏必须自包 `SafeArea(top: false)`，否则 iOS 上会被 home indicator 压住 | `storage_media`、`translate` 均已处理 |
| 11 | **AppSheet 有适用边界**：含「居中标题 + 左右操作按钮 + 多行输入」的复杂弹层（如 `quick_phrases` 的编辑表单）**不宜用 AppSheet 组件**，但外层 `showModalBottomSheet` 仍可统一换成 `showAppSheet`（它只负责圆角/SafeArea/键盘避让，`builder` 可以是任意 Widget） | 复杂内容自建 + `showAppSheet` 装载，是折中且低风险的做法 |
| 12 | **迁移顺手清掉的死代码**：`network_proxy` 的 `_divider`（无引用）、`_sheetOption` 里未使用的 `isDark`、`_showAddEditSheet` 里三个未使用局部变量、`theme_settings` 的重复 import（`provider` 与 `settings_provider` 各导入两次） | 均已处理，无功能影响 |

### 批次 3 新增经验

| # | 经验 | 结论 |
|---|------|------|
| 1 | **`states:` 依然不适用**：`local_snapshot` 的数据源是「本地可变状态 + `_refresh()` 可被多处调用（进入/备份后/删除后/固定后）」，不是「整页一个 Future」 | 维持手动三态（`if (_loading) AppLoading else if (empty) AppEmpty else 列表`），与 checklist 3b 一致 |
| 2 | **私有小控件里的手写按压三件套应一并收敛**：`_ActionChip` 原本自带 `GestureDetector + AnimatedScale + Haptics.soft()`，与 `IosTactileRow` 完全同构 | 换成 `IosTactileRow(pressedScale: 0.95, releaseDelay: 80ms)`，`_ActionChip` 从 `StatefulWidget` 降为 `StatelessWidget`。副作用（视为修正）：触觉由无条件改为受 设置→列表项触觉 约束 |
| 3 | **`IosTactileRow.releaseDelay` 就是为了这类「抬起后延迟复位」而加** | 原实现是 `onTapUp` 里 `Future.delayed(80ms)` 再复位；现在一行参数搞定，不用在页面里写 `Future.delayed` |
| 4 | **页面内重复定义卡片底色可以复用 features 层工具函数** | `local_snapshot` 里 `themeDark ? Colors.white10 : Colors.white.withOpacity(0.96)` 就是 `storageCardBackground(Theme.of(context))`，直接替换，避免再长一份 |
| 5 | **首帧空态闪烁**：`_loading` 初值 `false` + `_load()` 先 `await SharedPreferences` 再置 true，会先渲染一帧空态 | 初值改 `true`（属顺带修复，可单独回退） |
| 6 | **`about_page` 的 `_iosNavRow*` 仍未提取** | 等 `tts_services` / `display_settings` 迁移后一起提 `SettingsNavRow`，避免提了又改。**`default_model` 里发现了第 3 份副本（且是死代码，已删）**，说明这个复制已经失控，提取优先级上调 |
| 7 | **`AppSheet` 能完整承载「左对齐标题 + 多行输入 + 底部左右操作按钮」** | 之前记的边界是「居中标题 + 左右操作 + 多行输入不适用」；核对源码后 `AppSheet.title` 本身就是 **`Alignment.centerLeft`**，所以左对齐标题场景**完全适用**。本页两个提示词弹层已全量用 `AppSheet`（`children: [TextField]` + `footer: 操作行+变量说明`），`showAppSheet` 负责 SafeArea + 键盘避让 |
| 8 | **`_TactileRow` 的 60ms 复位延迟** 与 `local_snapshot` 的 80ms 同源 | `IosTactileRow.releaseDelay` 已覆盖，不必在页面里写 `Future.delayed` |
| 9 | **同页内两个结构相同的弹层应先合并再套模板** | 本页两个提示词弹层 110 行逐字重复，先用一个 `_PromptKind` 枚举 + extension 收敛差异（读/重置/保存/提示/变量说明），再套 `AppSheet`，比分别套模板省一半代码 |
| 10 | **`IosIconButton` 无触觉**（见变更记录） | ~~页面需要触觉时用局部包装保行为~~ **已解决**：引擎已加 `haptics` 参数，17 处调用点补齐 |
| 11 | **`SettingsNavRow` 系的三个真实差异点** | ① `theme_settings` 的卡跟随「纯色背景」开关（其余不跟）→ `pureBackground` 参数，内部用 `context.select` **短路订阅**（false 时不碰 Provider）；② `theme_settings` 的卡内边距是 6、其余是 4 → `verticalPadding`；③ `theme_settings` 的 divider indent 是 12、其余是 54（对齐 36 图标列）→ `indent`；④ `about` 的 `_iosNavRowSvgLeading` → 并入 `SettingsNavRow(svgAsset:)`，`icon`/`svgAsset` 二选一 + `assert` |
| 12 | **`IosCardPress` 与手写 `_TactileCard` 数学等价** | `Color.alphaBlend(c.withOpacity(a), bg)` == `Color.lerp(bg, c, a)`。所以 `assistant_settings` 的 `_TactileCard(pressed 叠 overlay)` 可以无损换成 `IosCardPress(pressedBlendStrength: isDark ? 0.06 : 0.04)`，且触觉开关（`hapticsOnCardTap`）也正好对上 |
| 13 | **脚本批量改代码的教训** | 用正则把 `_iosNavRowSvgLeading(\n context,` 换成 `SettingsNavRow(` 时，先做的前缀替换让后面的 `\s*context,\n` 正则失配，**留下 2 处悬空的 `context,` 参数行**。已修复；结论：多段正则要按「最长匹配优先」或一次性匹配整段，改完必须 grep 复核调用点 |
| 14 | **弹层里 `(ctx as Element).markNeedsBuild()` 应换成 `StatefulBuilder` 的 `setState`** | 两者效果等价（都是标脏重建），但 `setState` 语义明确、不需要 `as Element` 强转，作用域也更精确。`tts_services` 两处已改 |
| 15 | **`_sheetSelectRow` 是「无前置图标的导航行」**，而 `SettingsNavRow` 要求必须有 icon/svgAsset | 保留私有。若后续 `display_settings` / `multi_key_manager` 也出现这种行，再把 `SettingsNavRow` 的 leading 改成可选（去掉 assert）而不是现在就预留 |
| 16 | **私有 ≠ 冗余**：`_SmallTactileIcon`（透明度阶梯 0.9/0.6/0.3，无按压底色）与 `IosIconButton`（向白/黑混合 + 按压底色）视觉语义不同 | **保留私有**。收敛的标准是「逐字重复」或「语义完全等价」，不是「长得差不多」 |
| 17 | **行数不是收敛的度量**：`tts_services` 954 → 1067 行（**变长了**），因为原文件私有类全是单行密集写法（`final IconData icon; final Color color; ...` 挤一行），迁移时展开了成常规格式 | 真正的度量是：删掉 5 个私有 helper（≈89 行密集代码）+ 4 个弹层的 SafeArea/把手/键盘避让样板（≈30 行）；格式展开是可读性投资，不是退化 |
| 18 | ⚠️ **`SettingsNavRow` 的 `haptics` 默认值写错了（已修）** | 我最初把共享组件里的 `haptics` 写死成 `false`（照抄了 `about`/`sponsor` 的私有实现）。但对仓库原文复核后发现：`theme_settings` / `default_model` / `display_settings` 的私有 `_iosNavRow` 传的是 **`haptics: true`**，只有 `about` / `sponsor` 显式传 `false`。已把共享组件改为 `haptics = true` 默认，并给 `about`（7 处）/ `sponsor`（2 处）补回 `haptics: false`。**教训：共享组件的参数默认值要看全部源页面的私有副本，不能照抄第一个** |
| 19 | **无标题、无把手的「iOS 操作表」不适用 `AppSheet` 组件** | `AppSheet` 固定带顶部把手（grabber）与 `AppGap.xs` 内边距。`display_settings` 的 4 个选项弹层（字体来源/消息背景/安卓后台/语言）原本是无标题、行满宽铺满的，套 `AppSheet` 会改观感 → 改为 `showAppSheet` 装载 + 泛型 `_OptionSheet<T>` 自建内容（它只负责圆角/SafeArea/键盘避让） |
| 20 | **同页内 4 个形状一致的选项弹层应合成一个泛型组件** | 差异只有「选项文案 + 回传值」→ `_OptionSheet<T>` + `_SheetOption<T>`，4 个方法各只剩「声明 + 业务后置处理」。注意 `showAppSheet` 的 `isScrollControlled` 默认是 `true`，而这几个原弹层是默认的 `false`，**必须显式传 `false`**，否则弹层高度行为变了 |
| 21 | **滑杆弹层的主题与滑块圆点可整体抽走** | 字号/自动滚动/背景遮罩三个弹层共用一份 14 行的 `SfSliderThemeData` 和一个完全相同的 `thumbIcon` Container → `_sliderTheme(cs, isDark)` + `_sliderThumb(cs, isDark)` 两个顶层函数，省约 60 行 |
| 22 | ✅ **验证方式升级：本地真编译** | 沙箱此前连不上 GitHub，只能靠「括号平衡脚本 + 人工复核」。本轮网络恢复后：① `git clone` 到 `/tmp/mebot` 拿到全量源码；② 下载 Flutter **3.47.2 / Dart 3.13.2**（原 `/opt/flutter` 是 3.0.0 / Dart 2.17，解析不了项目 record 语法）；③ 把 30 个交付文件按 basename 映射回仓库路径，跑 `flutter analyze`。**注：官方 tarball 的 `bin/cache/flutter.version.json` 里 `frameworkVersion` 错写成 `3.0.0`（engine/dart 却是新的），会让 pub 以为 SDK 过旧而拒绝解析 `fl_chart >=0.66.0`；需手改成 `3.47.2`** |
| 23 | **`_iosSwitchRow` 暂不提升至共享层** | `display_settings` 的 4 个子页面共用一份私有 `_iosSwitchRow`，但仓库里另有 `backup` / `provider_detail` / `mcp_server_edit_sheet` / `add_provider_sheet` / `log_settings_sheet` / `theme_settings` 各自持有一份。跨文件重复度已够（≥6 份），但各自的默认参数与触觉策略需先比对 → 登记为**待办 E**，等批次 3 收官后统一提取 `SettingsSwitchRow` |
| 24 | 🐞 **引擎 bug：`AppPageStates<T>` 用了具体类型就在运行期崩** | 引擎的 `states` 字段原本是裸 `AppPageStates`（= `AppPageStates<dynamic>`）。传 `AppPageStates<String>` 时，编译期靠函数形参逆变 + `dynamic` 特例放行，但引擎读 `cfg.buildData` 会插入隐式转型检查，运行期抛 `_TypeError: '(BuildContext, String) => Text' is not a subtype of '(BuildContext, dynamic) => Widget'`。**修法：`AppPage<T>` / `_AppPageState<T>` / `_StatesScope<T>` 全链路泛型化**，`buildData` 全程保持 `T`。不使用 `states:` 的页面零改动（T 推断为 `dynamic`） |
| 25 | 🐞 **引擎 bug：`setState(() => _future = _fetch())` 会触发 Flutter 断言** | `=>` 闭包返回赋值表达式的值，也就是那个 `Future`。Flutter 会断言 `setState() callback argument returned a Future`。**影响：点任何错误态的「重试」按钮都会抛异常**（`_retry` 里这行是原引擎就有的）。**修法：先 `final next = _fetch();` 再用块体 `setState(() { _future = next; });`**。注意只改成 `setState(() => _future = next)` 仍然不行——块体才能丢弃返回值 |
| 26 | 🐞 **引擎 bug：重试时 future 的 error 会被当成「未处理异步异常」上报** | `setState` 要下一帧才重建，`FutureBuilder` 那时才订阅；而重试的 future 可能已经以错误完成 → 被判定为未处理的异步异常（测试里直接判失败，真机上走 `FlutterError.onError` 产生噪声日志）。**修法：`_fetch()` 里 `f.ignore()`** —— 实测 `ignore()` 只是把错误标记为已处理，`FutureBuilder` 之后订阅仍能正常拿到 `snapshot.hasError`。（`catchError` 不行：它的 `onError` 必须返回 future 的类型值） |
| 27 | **只有在真跑测试时才会暴露的 bug，靠 review 发现不了** | 上述 3 个引擎 bug（#24/#25/#26）在 12 个 widget 测试里有 6 个失败。此前 `test/app_page_test.dart` 从未真正执行过（沙箱 Flutter 3.0 跑不了），所以一直是「看起来对」。**结论：验证环境的可用性优先于迁移速度** —— 本轮第一件事就是把 Flutter 升到 3.47.2 并跑通 `analyze` + `test` |
| 28 | **「有没有把手」决定弹层走 `AppSheet` 还是 `showAppSheet`** | 经验 #19 说的是「无把手 → 自建」，但反过来：**原本就有把手的选项弹层，`AppSheet` 正好吃得下**。`multi_key_manager` 的策略弹层有把手 + 选中打勾 + 无标题 → 直接用 `AppSheet(children: [...])`，比 `display_settings` 的 `_OptionSheet` 还省事。**判断顺序：先看原弹层有无把手，有 → 试 `AppSheet`；无 → `showAppSheet` 自建** |
| 29 | **同页内形状一致的表单弹层应共用「头部 + 字段」两个 helper** | `multi_key_manager` 的添加/编辑弹层都是「把手 + 左关|居中标题 + N 个同形 TextField + 全宽主按钮」。抽 `_formSheetHeader(ctx, title)` 与 `_formField(ctx, {controller, hint, minLines, maxLines, keyboardType})` 后，两个方法各只剩「声明 + 业务后置处理」，**省掉约 90 行重复**。注意 `OutlineInputBorder.copyWith(borderSide:)` 可复用同一份 border 只改颜色 |
| 30 | **`IosTactileRow` 不传 `pressedScale` 就是不缩放**，对上原生的 `pressedScale: 1.00` | `multi_key_manager` 的策略行与 `_TactileRow(pressedScale: 1.00)` 等价（`pressedScale ?? 1.0`）。**不要顺手传 `1.0`** —— null 与 1.0 在当前实现下结果相同，但语义上「不缩放」更清晰，也避免以后引擎改默认值时被带着变 |
| 31 | **删死代码前先 grep 全部调用点，尤其是「只有一条分支用」的私有组件** | `multi_key_manager` 的 `_TactileScale` 只被 `_iosRow` 的 `onTap != null` 分支使用，而 3 个调用点全都没传 `onTap` → 组件 + 分支一起删。`_divider` / `_chooseDetectModel` 同为 0 引用。**这类死代码是「原本可配置」被产品改动后遗留的，静态分析只报私有未引用，不报分支未触发** |
| 32 | **跨 feature 复用要克制：宁可本地留一份，也不要反向依赖** | `provider/pages` 用 `settings/widgets/SettingsSectionCard` 会造成 provider → settings 的反向依赖。但全仓 `_iosSectionCard` 已有 **12 份**，现在是「三份同形不同名的共享件 + 一堆本地件」的尴尬状态 → 登记**待办 F**：批次 3 收官后统一提到 `shared/widgets/app_section_card.dart`，让 settings / storage / provider 三家都来依赖 shared，而不是互相依赖 |
| 33 | **`sort_child_properties_last` 与「语义参数顺序」冲突时用 `// ignore:` 而不是改顺序** | `AppSheet` 的自然读法是 title → children → footer，但 lint 要求 `children:` 放最后。把 `children` 挪到 `footer` 之后会让 4 个调用点都变得难读。项目里已有 13 处 `// ignore:` 先例，选它并在注释里写明原因 |
| 34 | **浮层底栏不要用 `bottom:` 槽位** | `bottom:` 会变成 `bottomNavigationBar`，**常驻占位并把 body 顶上去**。`providers_page` 的选择栏是「滑入/滑出」的浮层，必须盖在列表之上 → 保持 `body: Stack([列表, Positioned(bottom: 0, 浮层)])`。**判断标准：底栏是否常驻可见？是 → `bottom:`；否（有显隐动画）→ `Stack + Positioned`** |
| 35 | **页面自己处理了系统栏时，要关掉引擎的 `safeArea`** | `providers_page` 的列表要「贴底」，所以自己读 `MediaQuery.padding.bottom` 算出了底部留白。此时引擎再包一层 `SafeArea` 会**二次叠加**（`SafeArea` 只加 Padding，不改 `MediaQuery`，所以页面里读到的 inset 不会变小）。**判定方法：迁移前先 grep 页面里的 `MediaQuery.of(...).padding` / `viewInsets`，有手工处理就传 `safeArea: false`** |
| 36 | **「死代码」不止未引用的类，还有未读写的字段与未触发的分支** | `providers_page` 一次清出 5 类：`_items` 字段（声明后从未读写）、`_CapsuleButton`（65 行完整组件，0 调用点）、`_Pill`、`_DragHandle`（注释里已写 "removed per design" 但类没删）、`_tintPurpleSilicon`（方法 0 调用）、`isFirst` 局部变量（算了但没用）。**其中只有类是 analyzer 的 `unused_element` 能报的，字段/局部变量要靠 `unused_field` / `unused_local_variable`（warning），而「被注释废弃但类还在」只能靠人读** |
| 37 | **迁移到本页时「跨 feature 复用」的账要记清楚** | `multi_key_manager` 与 `providers_page` 都有与 `SettingsSectionCard` / `SettingsDivider` 逐值相同的私有件，但都选择本地保留（避免 provider → settings 反向依赖）。**记账方式：在文件头注释里写明「与 X 相同，待 待办 F 统一」，而不是默默复制一份。** 这样 待办 F 执行时有完整的清单 |
| 38 | 🚨 **`export` 不会把名字引入本库自身作用域**（本轮实锤） | shim/桶文件里 `typedef X = AppSectionCard;` 若只有 `export` 没有 `import`，typedef 全报 `undefined_class`，且**错误不在 shim 本身 而是传导到所有使用方页面**（`creation_with_non_type` / `invocation_of_non_function`，本案 78 个 error）。修复 = `import` + `export` **成对**。**两条纪律：① 桶文件必须 import + export 成对；② 每轮改完要跑一次全量 analyze —— 只跑改动文件会漏掉传导错误** |
| 39 | **居中标题 / 三段式头的弹层可以吃 `AppSheet`：`title` 留空，把标题当首个 child** | 此前规则是「居中标题/三段式 → `showAppSheet` + 全自建」，但 `AppSheet(title: null)` 会跳过左对齐标题、只保留把手/滚动/键盘避让，自建成本骤降。`backup_page` 的确认弹层（居中标题）与 WebDAV 设置弹层（左关|中题|右存）均按此落地。**与 #19/#28 合并后的完整判定：有把手 → `AppSheet`；标题居中或三段式 → `AppSheet(title: null)` + 首个 child 自绘头部；无把手、行满宽的操作表 → `showAppSheet` + 自建** |
| 40 | 🐞 **把 `builder: (ctx) { return StatefulBuilder(...) }` 拍平成 `builder: StatefulBuilder(...)` 后，内层的 `});` 会悬空** | 拍平前 `});` 的 `;` 闭合的是 **`return StatefulBuilder(...);` 语句**；拍平后它变成 named-argument 表达式，`;` 非法 → parser 报 `Expected to find ')'` 且**报错位置在几行之外的 `});`**，与出错点相距甚远。**坑上加坑：括号平衡脚本（纯计数）判定 OK**，因为字符层面确实配平（`;` 不是括号）。修复 = `});` → `}),`。**纪律：拍平 builder 闭包时，结尾三件套 `});` 要整体改写为 `}),`；验证以 `dart format --output=none` 能解析为准，别只信括号计数** |
| 41 | **`AppPage.title` 是 `String`，富标题走新增的 `titleWidget` 槽位** | `provider_detail` 的标题是「品牌头像 + 动态名称」，`Text(title)` 表达不了。引擎加 `Widget? titleWidget`，渲染 `titleWidget ?? Text(title)`——**默认路径一字不动，纯增量**。新增引擎槽位必须同步补 `app_page_test.dart` 用例（本批 +1 → 14 个） |
| 42 | **「PageView + 自绘 iOS 胶囊分段」不要套 segments(bottom)，走 `bottom:` 槽位** | 引擎 `segmentsMode: bottom` 渲染的是 Material `NavigationBar` 且 body 是 `segs[index].body` 单子树——**没有 PageView 滑动**，胶囊视觉也全丢。正确映射：`scrollable: false` + `bodyPadding: zero` + `body: PageView(...)` + `bottom: SafeArea(top:false, Padding(..., _BottomTabs(...)))`（**引擎对 `bottom:` 不包 SafeArea，自供**）。与经验 #34 合并：`bottom:` 槽位适合「常驻底栏」，无论它长得像不像导航栏 |
| 43 | **视觉基线不同的私有实现，保留并写明理由，不要硬并** | `provider_detail` 的 `_iosSectionCard` 背景公式是 `Color.lerp(surface, white, 6%/92%)`，与共享 `AppSectionCard` 的 `white10/white96` 不同——硬并会改变本页明暗观感。处置：保留私有 + 文件内 doc 注释写明「为何不并」。**与 #32 待办 F 的边界：待办 F 收敛的是「逐字相同」的副本，不同值 ≠ 冗余** |

### 批次 1 暴露的引擎/页面问题（记录在案，不阻塞迁移）

| # | 问题 | 处置 |
|---|------|------|
| 1 | **嵌套滚动是批次高频坑**：6 页里有 4 页必须 `scrollable: false`（自带 SCSV / `Expanded(ListView)` / `Center` 垂直居中 / `maxLines:null` TextField） | 已在 checklist 加 3c；本批逐页注明原因 |
| 2 | **`AppPage.title` 必填非空**，但 `more_page` 原设计无标题（`title: null`） | 本页传 `''` 占位（视觉等价）。若后续还有无标题页，建议把 `title` 改为 `String?`（改引擎须同步补测试） |
| 3 | `terminal_placeholder_page` 硬编码 `v0.0.28`，**已过期**（pubspec 现为 `0.0.37+37`） | 保留原值 + `TODO`，建议改用 `package_info_plus` 动态取版本 |
| 4 | `more_page` 硬编码中文 `'LLM排行榜'`，缺 l10n | 保留原值 + `TODO`，建议补 `app_*.arb` 后替换 |
| 5 | `google_fonts_picker_page` 每次 build 都 `GoogleFonts.asMap()` + 建表 + 排序 1500+ 项（筛选输入每敲一键触发一次） | 已改为静态缓存 + 过滤结果只算一次（附带修复，可单独回退） |
| 6 | `message_edit_page` 未使用的 `lucide_adapter` import | 已移除 |

---

## 一、技术底座（已完成，无需再动）

| 组件 | 文件 | 用途 |
|---|---|---|
| AppPage | `lib/shared/widgets/app_page.dart` | 页面骨架引擎（顶栏/分段/三态/底栏/抽屉槽位） |
| AppSegment / AppSegmentMode | 同上 | 分段模型：top=顶栏TabBar / bottom=页内底部分段 |
| AppPageStates | 同上 | AsyncSnapshot 三态状态机配置（新增 `reloadKey` 控制重载） |
| AppLoading / AppError / AppEmpty | `lib/shared/widgets/app_states.dart` | 三态占位组件 |
| AppSheet / showAppSheet | `lib/shared/widgets/app_sheet.dart` | iOS mini-sheet 底部弹层模板 |
| 设计 Token | `lib/theme/design_tokens.dart` | AppGap / AppRadius / AppPagePadding / AppText |

### 已迁移样板（✅ 5 个，作为参考范例）

| 页面 | 用到的特性 | 摘要 |
|---|---|---|
| `settings/pages/settings_page.dart` | AppPage 基础（leading/title/body） | 首个迁移范例 |
| `storage/pages/storage_page.dart` | 三态 + 自定义 leading/actions | **Provider 驱动手动三态**（未用 `states:`，见下方约定） |
| `mcp/pages/mcp_tool_detail_page.dart` | segments top + AppEmpty | 顶栏 Tab 双落点 |
| `chat/widgets/reasoning_budget_sheet.dart` | AppSheet | 弹层样板收敛 |
| `provider/pages/provider_network_page.dart` | AppPage + 表单 body + Token 化 | ✅ 批次 1 首个完成（2026-09-07） |

> **⚠️ 三态使用约定（重要）**
> - `states:` 槽位是「一次性 Future」语义，**适合开页拉一次的页面**（如统计/详情）。
> - **Provider / ChangeNotifier 驱动的页面请勿使用 `states:`**，改为在 body 里手动判断
>   `provider.loading` / `provider.error`，直接渲染 `AppLoading` / `AppError` / `AppEmpty`
>   （参考 `storage_page.dart`）。
> - 需要重载时改变 `AppPageStates.reloadKey`；父级单纯重建不会重复拉取。
> - 若 body 自带 `ListView`/`SingleChildScrollView`，请设 `scrollable: false`，避免嵌套滚动。

---

## 二、待迁移页面清单（已盘点）

> 以下来自 `grep -rln "return Scaffold(" lib/features`，共 **34 个**手写 Scaffold。
> 按**行数由小到大（风险由低到高）**分 4 批。

### 批次 0 — 明示不迁移（✅ 无需动）

| 页面 | 行数 | 原因 |
|---|---|---|
| `home/pages/home_page.dart` | — | 入口级复杂页，6245 行，单独治理 |
| `assistant/pages/assistant_settings_edit_page.dart` | 6148 | 超级单体，风险最高，暂缓 |
| `chat/pages/image_viewer_page.dart`（Scan：全屏） | — | 全屏沉浸页，不适用模板 |
| `scan/pages/qr_scan_page.dart` | 66 | 全屏相机页，不适用模板 |
| `chat/pages/html_preview_page.dart` | 81 | Web 预览全屏页，不适用模板 |
| `storage/pages/log_viewer_page.dart` | 266 | 命令日志全屏查看器，不适用模板 |

### 批次 1 — 简单页（≤150 行，快速迁移 6 个）

| 页面 | 行数 | 迁移要点 |
|---|---|---|
| `chat/pages/select_copy_page.dart` | 60 | 纯 body，AppPage 基础用法 |
| `terminal/pages/terminal_placeholder_page.dart` | 74 | AppPage 基础 + AppEmpty 占位 |
| `chat/pages/message_edit_page.dart` | 81 | AppPage + 自定义 actions |
| `settings/pages/google_fonts_picker_page.dart` | 84 | AppPage + 列表 body |
| `settings/pages/more_page.dart` | 113 | AppPage 基础 |
| `provider/pages/provider_network_page.dart` | 155 | AppPage + 表单 body（**✅ 已完成**） |

### 批次 2 — 中等页（150–400 行，13 个）

| 页面 | 行数 | 迁移要点 |
|---|---|---|
| `assistant/pages/tags_manager_page.dart` | 201 | AppPage + 列表 + bottom 槽位 |
| `settings/pages/theme_settings_page.dart` | 248 | AppPage + indicators |
| `storage/pages/storage_log_page.dart` | 251 | AppPage + 列表 |
| `storage/pages/storage_cache_page.dart` | 275 | AppPage + 列表三态 |
| `storage/pages/storage_detail_page.dart` | 330 | AppPage + 三态 |
| `chat/pages/chat_history_page.dart` | 341 | AppPage + 列表 + 空态 |
| `mcp/pages/mcp_server_detail_page.dart` | 353 | AppPage + **segments top**（含 TabBar） |
| `settings/pages/sponsor_page.dart` | 398 | AppPage 基础 + 卡片 body |
| `translate/pages/translate_page.dart` | 426 | AppPage + 输入区 + actions |
| `settings/pages/network_proxy_page.dart` | 478 | AppPage + 表单 + 弹层 |
| `storage/pages/storage_media_page.dart` | 497 | AppPage + 网格 + 三态 |
| `mcp/pages/mcp_page.dart` | 504 | AppPage + 列表 + 弹层 |
| `quick_phrase/pages/quick_phrases_page.dart` | 564 | AppPage + 列表 + bottom sheet |

### 批次 3 — 复杂页（>400 行，8 个）

| 页面 | 行数 | 迁移要点 |
|---|---|---|
| `model/pages/default_model_page.dart` | 574 | AppPage + 弹层 + 列表 |
| `assistant/pages/assistant_settings_page.dart` | 627 | AppPage + 多段列表 |
| `storage/pages/local_snapshot_page.dart` | 727 | AppPage + 三态 + 列表 |
| `settings/pages/about_page.dart` | 814 | AppPage + 卡片 + 弹层 |
| `settings/pages/tts_services_page.dart` | 954 | AppPage + 列表 + 多弹层 |
| `provider/pages/multi_key_manager_page.dart` | 1025 | AppPage + 列表 + 多弹层 |
| `settings/pages/display_settings_page.dart` | 1086 | AppPage + 多弹层 |
| `provider/pages/providers_page.dart` | 1123 | AppPage + segments 或列表 |

### 批次 4 — 大复杂度页（>1200 行，4 个）

| 页面 | 行数 | 迁移要点 |
|---|---|---|
| `settings/pages/usage_stats_page.dart` | 1297 | AppPage + 图表 + segments top |
| `backup/pages/backup_page.dart` | 1404 | AppPage + 多区卡片 |
| `search/pages/search_services_page.dart` | 1533 | AppPage + 表单 + 弹层 |
| `provider/pages/provider_detail_page.dart` | 2412（含 bottom）| AppPage + 富标题 + `bottom:` 槽位（自管 PageView；原计划 segments bottom，实际引擎该模式无滑动且样式不符，改走 `bottom:`，见经验 #42） |

---

## 三、迁移步骤模板（每个页面照此执行）

每迁一个页面，按下面 checklist 走，完成即在下方"进度登记"打勾。

```
[ ] 1. 通读页面，识别用到的槽位（leading/actions/segments/states/bottom/sheet）
[ ] 2. 用 AppPage 替换手写 Scaffold + AppBar
[ ] 3. body 里的 loading/error/empty 分支 → AppLoading/AppError/AppEmpty
[ ] 3b. 若页面由 Provider 驱动 → 手动三态，不要用 states: 槽位
[ ] 3c. 若 body 自带 ListView/ScrollView → 设 scrollable: false，避免嵌套滚动
[ ] 3d. 若 body 是 Column → 必须 crossAxisAlignment: CrossAxisAlignment.stretch，
      否则 Column 默认 center 会把子项宽度放宽，卡片缩成内容宽度
[ ] 4. TabBar + TabBarView → segments: [AppSegment(...)]（segmentsMode: top）
[ ] 5. 页内底部导航 → segments（segmentsMode: bottom）或 bottom 槽位
[ ] 6. showModalBottomSheet 简单弹层 → showAppSheet + AppSheet
[ ] 7. 魔法数字 padding → AppPagePadding / AppGap / AppRadius
[ ] 8. 移除页面私有 _TactileIconButton 复制 → IosIconButton（共享）；
      自绘按压行卡 → IosTactileRow + IosPressColor（不再新写私有 _TactileRow/_AnimatedPressColor）
[ ] 9. flutter analyze 无 error / unused
[ ] 10. 编译（本机 flutter / CI Android）通过
[ ] 11. 真机入口验证：返回、顶栏、三态、Tab 切换、弹层交互
```

---

## 四、进度登记表

> 每完成一批勾选一个区块。

### ✅ 已完成
- [x] `settings/pages/settings_page.dart`
- [x] `storage/pages/storage_page.dart`
- [x] `mcp/pages/mcp_tool_detail_page.dart`
- [x] `chat/widgets/reasoning_budget_sheet.dart`

### ✅ 批次 1（简单页）— 完成（6/6）
- [x] `provider/pages/provider_network_page.dart` ← 表单 body
- [x] `chat/pages/select_copy_page.dart` ← 纯 body + actions（`scrollable:false`）
- [x] `terminal/pages/terminal_placeholder_page.dart` ← 居中占位（`scrollable:false`）
- [x] `chat/pages/message_edit_page.dart` ← AppPage + 自定义 actions（`scrollable:false`）
- [x] `settings/pages/google_fonts_picker_page.dart` ← 列表 body（`scrollable:false` + `Expanded`）
- [x] `settings/pages/more_page.dart` ← AppPage 基础（无标题，传 `''` 占位）

### ✅ 批次 2（中等页）— 完成（13/13）
- [x] `mcp/pages/mcp_server_detail_page.dart` ← **segments top 样板**（TabBar + TabBarView 交给引擎）
- [x] `assistant/pages/tags_manager_page.dart` ← 列表 + bottom（`scrollable:false`，ReorderableListView）
- [x] `chat/pages/chat_history_page.dart` ← 列表 + 空态 → AppEmpty（`scrollable:false`）
- [x] `settings/pages/sponsor_page.dart` ← 卡片 body + 局部 Future 手动三态 + 私有按钮收敛
- [x] `storage/pages/storage_log_page.dart` ← 明细列表（`Column` + stretch），空态 → AppEmpty，`debugPrint` → `Logger.e`
- [x] `storage/pages/storage_cache_page.dart` ← 同上；另把两处逐字重复的清理确认弹窗抽成 `_confirmClear()`
- [x] `storage/pages/storage_detail_page.dart` ← 同上（含「管理副本」入口卡）
- [x] `storage/pages/storage_media_page.dart` ← **首个 `bottom:` 槽位样板**：网格列表（`scrollable:false`）+ 底部全选/删除条
- [x] `mcp/pages/mcp_page.dart` ← 列表 + **`AppSheet` 收敛错误详情弹层** + 私有 `_TactileIconButton` → `IosIconButton`
- [x] `settings/pages/network_proxy_page.dart` ← 表单 body + 手写 sheet → `AppSheet`；删死代码 `_divider`
- [x] `quick_phrase/pages/quick_phrases_page.dart` ← `ReorderableListView`（`scrollable:false`）+ 空态 → `AppEmpty`；复杂编辑弹层**只收敛外层 `showAppSheet`**
- [x] `settings/pages/theme_settings_page.dart` ← 开关/配色列表；清掉重复 import
- [x] `translate/pages/translate_page.dart` ← **第二个 `bottom:` 槽位样板**（底栏补 `SafeArea(top:false)`）

### ✅ 批次 3（复杂页）— 已完成（8/8）
- [x] `settings/pages/about_page.dart` ← 信息卡 + 链接列表；彩蛋弹层保持自建；私有触觉副本收敛；`_iosNavRow*` → `SettingsNavRow`
- [x] `storage/pages/local_snapshot_page.dart` ← 设置卡 + 三态列表；`_ActionChip` 收敛到 `IosTactileRow`；修首帧空态闪烁
- [x] `model/pages/default_model_page.dart` ← 三张模型卡；两个重复弹层合并 + `AppSheet`；清 8 处死代码（574→403 行）
- [x] `assistant/pages/assistant_settings_page.dart` ← 可拖拽列表（`scrollable:false`）；新增弹层 → `showAppSheet`；`_TactileCard` → `IosCardPress`（627→549 行）
- [x] `settings/pages/tts_services_page.dart` ← 系统行 + 网络列表；**4 个弹层**分别收敛（AppSheet ×2 / showAppSheet ×2）；5 个私有 helper 收敛；`_SmallTactileIcon` 有意保留私有
- [x] `settings/pages/display_settings_page.dart` ← **首个「一页带 4 个子页面」的样板**；13 行吃 `SettingsNavRow` 红利；4 个选项弹层 → `_OptionSheet<T>`；3 个滑杆弹层 → `showAppSheet`（1086→904 行）
- [x] `provider/pages/multi_key_manager_page.dart` ← **provider 家族首个落地页**；AppBar 3 个动作 + 每 key 的编辑/删除 → `IosIconButton(haptics:true, minSize:44)`；策略行 → `IosTactileRow+IosPressColor`；策略弹层 → `AppSheet`（带把手 + 选中打勾）；添加/编辑两个表单弹层 → `showAppSheet` + 共用 `_formSheetHeader`/`_formField`；删 3 处死代码（`_TactileScale`/`_divider`/`_chooseDetectModel`）+ 2 个重复 import + 1 个无引用 import（1025→802 行）
- [x] `provider/pages/providers_page.dart` ← **批次 3 收官页**；`ReorderableListView` → **`scrollable:false`** + `bodyPadding: zero`（列表自带 `16,8,16,0`）；**`safeArea: false`**（本页自己用 `MediaQuery.padding.bottom` 给列表留系统栏，引擎再包会二次叠加）；选择栏是「滑入/滑出」浮层 → **坚持 `Stack + Positioned`，不用 `bottom:` 槽位**（后者会常驻占位并把 body 顶上去）；多选导出弹层 → `showAppSheet`（居中标题故自建）；删 5 处死代码（`_items` 字段 / `_CapsuleButton` 65 行 / `_Pill` / `_DragHandle` / `_tintPurpleSilicon` / `isFirst`）+ 1 个重复 import（1123→941 行）

### ✅ 批次 4（大复杂度页）— 完成（4/4 · 全项目页面收官）
- [x] `settings/pages/usage_stats_page.dart` ← **首个 `states:` 槽位生产页**（手写 FutureBuilder 三态全删；刷新 → `reloadKey`）
- [x] `backup/pages/backup_page.dart` ← 4 份私有 iOS 副本收敛 shared；3 个弹层 → AppSheet；1405→1122 行
- [x] `search/pages/search_services_page.dart` ← 两层手势合并；4 个弹层分级收敛；清死代码 9 处；1533→1377 行
- [x] `provider/pages/provider_detail_page.dart` ← **全仓最大页（2412 行）收官**；`titleWidget` 富标题（引擎新槽位首个使用者）；`PageView`+自绘胶囊 → `bottom:` 槽位（**弃用 segments bottom**，经验 #42）；私有 `_TactileRow`/`_TactileIconButton` 全删；类型弹层 → `AppSheet`、模型选择 → `showAppSheet`+`DraggableScrollableSheet`；死代码 ×4（`_switchRow`/`_checkboxRow`/`_buildProviderTypeSelector`/`_preferMonochromeWhite`）；**2412→2116 行，净新增 issues 0**

---

## 五、迁移顺序理由（建议按此推进）

1. **批次 1 优先**：6 个简单页，单页 ≤30 分钟改完，风险极低，快速积累一致性
2. **批次 2**：引入 TabBar（mcp_server_detail）和三态，验证 segments top + states
3. **批次 3**：多弹层页面（tts/display/multi_key），把 69 处 showModalBottomSheet 逐步收敛到 AppSheet
4. **批次 4 最后**：provider_detail 是唯一已用 bottomNavigationBar 的页面，最终以 **`bottom:` 槽位 + 自管 PageView** 落地（segments(bottom) 引擎渲染 Material NavigationBar 且无滑动，不适合 iOS 胶囊分段，经验 #42）；**34/34 页全部迁移完成**

> ⚠️ 每批完成后**必须编译验证**（本机 flutter analyze + CI Android），再进下一批。
> 已迁移页的回归以手工真机为主，不引入额外测试框架。
>
> ✅ **回归基线已就位**：`test/app_page_test.dart`（**14 个用例**）覆盖
> 基础骨架 / `scrollable:false` / leading / **`titleWidget` 富标题** / segments top / segments bottom / bottom 槽位 /
> states 四态，以及 **reloadKey 重载策略的 3 条回归断言**。
> 引擎后续任何改动请先 `flutter test test/app_page_test.dart`，全绿再继续迁移。
