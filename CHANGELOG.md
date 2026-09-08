# Changelog — MiniMe-Core

All notable changes to this project are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); versioning: `0.0.x` patch 递增，里程碑由用户拍板升 minor。

> 每个版本三档受众：**📣 For Users**（人话讲收益）/ **🔧 For Developers**（工程细节与迁移）/ **🤖 For Agents**（符号级变更 + 行为语义 + 坑位预警）。发布时同步 GitHub Release（用户档扩充版）与本文件（开发者档 + 模型档）。

## [Unreleased]

### 🔧 For Developers
- **Added**：AI 协助开发规范体系——`AGENTS.md`（环境现实 / 7 条带事故锚点的铁律 / 行动边界三级 / 发布 SOP / 版本日志三档）、`CLAUDE.md` 桥接、本文件（Keep a Changelog 三档结构）。
- **Added**：CI android job 接入 `flutter analyze` 观察步骤（`continue-on-error: true`）。

### 🤖 For Agents
- 首轮 analyze 基线（2026-09-08）：**3074 issues**（~235 warning；585 条 `deprecated_member_use` 集中在 `lib/desktop/`，desktop_settings_page.dart 单文件 244 条）。硬化策略与增量红线见 `AGENTS.md` §5.4。
- 本文件三档结构本身是规范的一部分：发版时用户档→Release body，开发者档+模型档→本文件，勿混写。

## [0.0.43] - 2026-09-08

### 📣 For Users
- 统计页「聊天热力图」彻底重做：配色更真实反映你的使用分布，电脑上悬停即看每日详情，顶部新增总消息数，进入页面有波浪入场动画。
- 繁体中文界面修复：统计页此前有 23 处显示为简体，已全部纠正。

### 🔧 For Developers
- **Changed**：`stats_heatmap.dart` 整体重写——颜色分级由 `count/maxCount` 线性改为四分位标尺（`_HeatmapScale`，窗口内非零计数取 Q1/Q2/Q3）；新增 MouseRegion 悬停浮层、头部总计（`NumberFormat.decimalPattern` 千分位）、列级入场动画（`AnimationController` + painter `repaint`）、月份标签「放不下跳过」、`firstDayOfWeekIndex` 本地周首。
- **Changed**：l10n 新增 `statsHeatmapSummary` / `statsHeatmapNoActivity`（4 ARB + 3 生成 Dart + `StatsL10n`）。
- **Fixed**：`AppLocalizationsZhHant` 类 19 个 getter + 4 个方法返回简体值，全部对齐 `app_zh_Hant.arb`。

### 🤖 For Agents
- `MaterialLocalizations` 无 `firstDayOfWeek`；正确 API 为 `firstDayOfWeekIndex`（int，**0=周日** 基准）。`narrowWeekdays` **固定周日起始**（intl ICU 数据原样），映射本地周序用 `narrow[(firstDayIndex + i) % 7]`。
- 引入 `package:intl` 后，dart:ui 的 `TextDirection` 被遮蔽——需要 enum 用 `import 'dart:ui' as ui show TextDirection;` + `ui.TextDirection.ltr`。
- `RRect` 存在 `inflate(double)`（画描边可用）；`Color.a` 新 API 可用（工程 Flutter 3.35）。
- 坑：`lib/l10n/app_localizations*.dart` 是仓库内生成物，CI 可能按 ARB 重生成——手改它们必须与 ARB 语义严格一致（见 AGENTS.md T2）。
- 涉及文件：`lib/features/settings/widgets/stats_heatmap.dart`（重写）、`stats_l10n.dart`、`lib/l10n/*`（7 文件）。

## [0.0.42] - 2026-09-08

### 📣 For Users
- 统计页全新改版：用量趋势改为堆叠柱状图（可看各模型构成），新增总览卡片与模型/助手/话题三张排行表，支持按时间范围筛选。

### 🔧 For Developers
- **Added**：数据层 `lib/core/services/stats/stats_aggregator.dart`（`StatsSnapshot.compute`，range→window→聚合三段式）；页面拆分为 6 个 widget 文件 + 重写 `usage_stats_page.dart`（1312→约 270 行）。
- **Added**：注入 35 个 `stats*` l10n key（4 语种）。
- **Changed**：趋势图用 fl_chart 0.68 `BarChartRodStackItem` 堆叠；tooltip 走 `BarTouchTooltipData` 新签名（`getTooltipColor` 等）。

### 🤖 For Agents
- fl_chart 0.68：`BarChartRodData` 堆叠 = `toY: 累计值, color: transparent, rodStackItems: [...]`；`BarTooltipItem(text, style, {children})`；`FlGridData.horizontalInterval` / `SideTitles.interval` 断言**必须非零**（`_niceInterval` 处理）。
- 坑：`String.characters` 扩展来自 `package:characters`，**必须显式 import**（v0.0.42 首轮 CI 失败主因，两处）。
- 坑：`StatsSnapshot` 哨兵常量 `__stats_unknown_model__` 等曾混入 NUL 字节——脚本批量写源码后按 AGENTS.md T5 自校验。

## [0.0.41] - 2026-09-08

### 📣 For Users
- 存储页「助手」分类重新定义：不再只收图片，而是收助手产出的**各类型文件**（生图、头像等），为后续 agent 工作区做准备；「图片」收纳所有图片来源。

### 🔧 For Developers
- **Changed**：存储分类判定重构；修复来源筛选 / 排序 / 环形图与列表数据失配。

### 🤖 For Agents
- `StatsSnapshot` 哨兵 key 体系（`globalAssistantKey` 等）在本版确立占位语义：占位名通过 l10n key（`statsGlobalAssistant` 等）本地化，不可硬编码中文。

## [0.0.40] - 2026-09-08

### 📣 For Users
- 修复存储页「图片」与「助手」两个分类数据完全相同的重复计数问题；助手生成图片正确归档到头像目录。

### 🔧 For Developers
- **Fixed**：图片/助手分类重复计数；助手生图落盘路径改为 `avatars`。

[Unreleased]: https://github.com/Lisir2002/Me-Bot/compare/v0.0.43...HEAD
[0.0.43]: https://github.com/Lisir2002/Me-Bot/compare/v0.0.42...v0.0.43
[0.0.42]: https://github.com/Lisir2002/Me-Bot/compare/v0.0.41...v0.0.42
[0.0.41]: https://github.com/Lisir2002/Me-Bot/compare/v0.0.40...v0.0.41
[0.0.40]: https://github.com/Lisir2002/Me-Bot/compare/v0.0.39...v0.0.40
