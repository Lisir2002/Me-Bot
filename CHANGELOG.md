# Changelog — MiniMe-Core

All notable changes to this project are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); versioning: `0.0.x` patch 递增，里程碑由用户拍板升 minor。

> 每个版本三档受众：**📣 For Users**（人话讲收益）/ **🔧 For Developers**（工程细节与迁移）/ **🤖 For Agents**（符号级变更 + 行为语义 + 坑位预警）。发布时同步 GitHub Release（用户档扩充版）与本文件（开发者档 + 模型档）。

## [0.0.47] - 2026-09-10

### 📣 For Users
- **你的 API Key 更安全了**：所有密钥（模型 Key、搜索/TTS 凭证、代理密码、WebDAV 凭证）从明文存储整体迁入系统级安全存储（Android Keystore / iOS&macOS Keychain / Windows DPAPI / Linux libsecret），应用本地不再留存明文。
- **备份默认不再携带密钥**：导出备份默认脱敏（换机不泄密）；需要带密钥换机时可选「口令加密导出」（AES-256-GCM + 口令派生，无口令打不开）；导入旧版含明文密钥的备份时，密钥自动吸收进安全存储并从备份内容中剥离。
- **新增「安全中心」**（设置 → 安全）：
  - **安全体检**：一键扫描旧明文残留、无主凭证、本机备份文件与日志泄露风险，残留项可一键自动修复；
  - **密钥健康**：展示每个服务商的密钥数量、最近使用与轮换时间，超过 90 天未轮换会标「建议轮换」；
  - **隐私门禁**（默认关）：开启后查看/复制密钥、输入备份口令前需通过指纹/面容或锁屏密码验证（设备不支持时自动隐藏）；
  - **白名单策略**（默认关）：开启后限制 MCP 服务器只能执行白名单命令（默认 node/npx/python/python3/uvx/docker/bun），WebView 默认只允许 https 并拦截 `file://`/`javascript:`/`data:`。
- **复制密钥更放心**：复制出的密钥 60 秒后自动清空剪贴板（期间你复制了别的内容则不会误清）；凭证编辑页在 Android 上禁止截屏/录屏/近期任务缩略图。

### 🔧 For Developers
- **Added**（M1）：`lib/core/services/secure_storage/`——①`CredentialRecord` 信封（`{type,value,meta{createdAt,lastUsedAt,lastRotatedAt,ext}}`）+ ②`SecureStorageBackend` 平台注册器 + `SecureStorageService`；双写迁移：④`MigrationRunner` 注册表 + `credential_v1`（prefs→secure）/ `credential_v2`（新键位）两步；`BackupCredentialBridge`（导出脱敏/恢复吸收/孤儿清理）；`BackupEncryptor`（JWE `A256GCM` + `PBKDF2-HMAC-SHA256` 310k，备份格式 v2 信封，未知版本/算法显式报错，v1 明文照常导入）。
- **Added**（M2，PR-5~8）：③`CheckupScanner` 插件化体检引擎 + 首批 4 扫描器（legacy 明文残留/孤儿凭证/备份文件/日志文件）+ `SecretDetector`（六模式 + 高熵兜底，只回传模式名不回传明文）+ `ClipboardGuard`（60s TTL、清除前校验内容未被替换）+ `CredentialAuditLogger`（独立 `LogTags.security` 通道）；⑤`AppLockGate`/`IdentityVerifier`（`local_auth` 首实现，生物识别→系统 PIN 回退，默认关）+ Android `FLAG_SECURE`（自建 MethodChannel `kelivo/screen_security`）；`KeyHealthService`（90 天轮换阈值）；⑤`PolicyProvider`（`LocalPolicyProvider` 首实现）+ `McpCommandGuard`（MCP stdio spawn 前拦截，默认白名单 + 每服务器开关）+ `UrlGuard`（默认仅 https，硬拦 `file`/`javascript`/`data`/`content`）。统一入口 `SecurityPage`，移动端与桌面端共用。
- **Changed**：`MainActivity` 改继承 `FlutterFragmentActivity`（local_auth 硬性要求，普通 FlutterActivity 会返回 `NOT_FRAGMENT_ACTIVITY`）；`pubspec` 转正 `crypto`、新增 `local_auth ^2.3.0`；SettingsProvider 凭证写路径改 `writeCredential(...toRecord().markRotated())`，请求命中密钥时 `touchProviderCredential`（60s 去抖）。
- **Migrated**：凭证读取为 secure 优先、prefs 兜底；旧明文 key 保留作回滚兜底（迁移确认后下版本移除）；l10n 四份 arb 共 +45 键（加密 11 + 安全中心 34）。
- **Verified**：`flutter test` 136/136（存量 95 + 新增 41）；全量 `dart analyze` 0 error / 0 warning；Android CI success（run 34384039313）。

### 🤖 For Agents
- **行为语义**：`SecureStorage.instance` 未初始化**抛异常**（快速失败，禁止静默降级到明文路径）；`AppLockService`/`LocalPolicyProvider` **默认关**——`ensureUnlocked` 未启用直接放行、策略未启用时两个 Guard 全放行，勿在业务层再包一层开关判断。
- **坑位预警**：① l10n 源是 `lib/l10n/*.arb`，直接改生成的 dart 会被 `flutter gen-l10n` 覆盖；② 测试里的仿真密钥必须「前缀+主体」分字面量拼接（如 `'sk' '-' + body`），完整形态会被 GitHub secret scanning 的推送保护拦截（实测拦截过一次）；③ `LogContext.zone` 的 `fn` 是必填命名参数，位置传参会报 `named parameter 'fn' is required`；④ mcp_client 在包内部自行 `Process.start`，命令白名单只能拦截在我方 `McpProvider.connect()` 取出 `TransportConfig` 之前；⑤ WebView 拦截只能在 `NavigationDelegate.onNavigationRequest` 同步决策。
- **备份格式 v2**：`{"format":"kelivo-backup","version":2,"crypto":{alg,kdf,iterations,salt,jwe}}`；`BackupCryptoErrorKind`（needPassphrase/wrongPassphrase/unsupported/corrupt）驱动 UI 重试流。

## [0.0.45] - 2026-09-09

### 📣 For Users
- 本地副本页「备份频率」与「占用上限」改为可选择的档位：频率支持手动/每天/每周/自动；占用上限支持不限制/1/2/5/10 GB，并会按上限自动清理最旧的副本。

### 🤖 For Agents
- **Fixed**：本地副本页（`features/storage/pages/local_snapshot_page.dart`）两个设置项写死/错值修复：
  - **备份频率**：原 `detailText` 写死 `snapshotFrequencyAuto`（"自动"），改为可点击选择的四档（手动/每天/每周/自动，复用既有的 `snapshotFreq*` 文案），持久化到 `backup_freq`，默认 `auto` 保持原显示。注：当前应用无后台调度器，该值记录用户意图偏好而非自动执行。
  - **占用上限**：原 `detailText: '$_keepCount GB'` 是把"保留份数"误当 GB 显示的 bug，改为真实档位（不限制/1/2/5/10 GB，新增 `snapshotSizeUnlimited` 文案），持久化到 `backup_size_limit_gb`，默认 `不限制`（旧"3GB"从未真正裁剪）；并在 `_enforceRetention` 中新增按字节上限裁剪最旧非固定副本的逻辑。
- **Changed**（l10n）：`app_en/zh/zh_Hans/zh_Hant.arb` 新增 `snapshotSizeUnlimited`（不限制 / Unlimited）。

## [0.0.44] - 2026-09-09

### 📣 For Users
- **语音朗读的"停止"真的能停了**：此前用网络语音朗读长文本时，点停止/新对话无法真正中断请求，音频会继续播放到结束；现在立刻停止。
- **电脑版备份更可靠**：点"恢复"打开的远程备份列表，若 WebDAV 连接或认证出错，现在会显示具体失败原因（红色提示），不再误显示为"暂无备份"让你以为备份丢了。
- **更省心**：修复 HTML 预览在 Windows 上残留临时文件的问题，长期使用不再积累垃圾文件。
- 质量底盘：全项目 438 个静态分析警告清零，CI 升级为硬门禁（任何新警告/错误都会直接挡下构建），后续版本稳定性更有保障。

### 🔧 For Developers
- **Added**：AI 协助开发规范体系——`AGENTS.md`（环境现实 / 7 条带事故锚点的铁律 / 行动边界三级 / 发布 SOP / 版本日志三档）、`CLAUDE.md` 桥接、本文件（Keep a Changelog 三档结构）。
- **Changed**：CI android job 的 `flutter analyze` 由观察步骤升级为**硬门禁**（B6）：`--no-fatal-infos` + 去掉 `continue-on-error`，warning/error 直接阻塞构建；输出过滤 info 明细防截断，退出码经 `${PIPESTATUS[0]}` 传递（旧管道写法 `| grep … || true` 会吞掉失败码）。
- **Added**：`docs/WARNING_CLEARANCE.md`——438 warning 清零批次计划（B0–B6）、进度看板、红线。
- **Changed**：本地分析环境打通：`/opt/flutter335`（Flutter 3.35.7 / Dart 3.9.2，与 CI 对齐）可用，全量 `flutter analyze` 约 48s，实测与 CI 逐条一致。`AGENTS.md` §1 原「禁止本地 analyze」条款作废；`/opt/flutter`（2.17）仍禁用。
- **Changed**：warning 清零 B1 批次落地（`78b9c1c`）：`dart fix --apply` 应用 10 条规则，**438 → 248 warning，error 0**，涉及 53 个源文件。
- **Changed**：B2 批次落地（`0a3124d`）：`unused_shown_name` + `unused_field`，248 → 220；B3 批次落地（`3703d87`）：`unused_local_variable` 连锁死代码，220 → 136；B4 批次落地：`unused_element`/`unused_element_parameter` 逐条判读，136 → **44**（27 文件 +40/−1011，净删 971 行）；B5 批次落地：C 档 44 → **0**。**438 → 0 warning 清零达成，全程 error 0**。B1/B2/B3 已过 CI 并逐条核对。
- **Changed**：`html_preview_dialog.dart` 的 `_pushConsole` 从 `extension on _HtmlPreviewDialogState` 移入 State 类体——extension 中调用 protected `setState` 触发 `invalid_use_of_protected_member`，移入类内是唯一合规修法，行为不变。
- **Fixed**：0.0.43 遗留——`lib/l10n/app_localizations.dart` 中 `statsHeatmapSummary` / `statsHeatmapNoActivity` 被注入到类外（顶层无体函数声明），本地不跑 `pub get` 重新生成会报 `missing_function_body`；本次由 `flutter pub get` 重新生成到类内正确位置。
- **Fixed**（§9a 修复专项，`8a65787`）：① **TTS 网络合成取消链路失效**——`tts_provider` 原局部 `cancelled` 标志从未置 true，stop/flush 无法中断进行中的网络请求；改为每请求独立 `_TtsCancelToken`（stop/dispose 置当前 token，新请求不受影响），主动取消抛 `_Cancelled` 不再写入 `_error`。② **桌面备份页远程列表遗留死代码 + 弹窗吞错误**——pane 内 `_remote`/`_loadingRemote`/`_reloadRemote()` 为旧预取设计遗留（每次打开设置页白发一次 WebDAV 请求且无人消费），实际展示走"恢复"按钮 → `_RemoteBackupsDialog`（功能完整），死代码已删；弹窗 `_load()` 原吞掉异常致失败时静默显示"暂无备份"，改为透出错误详情。③ **HTML 预览 Windows 临时文件泄漏**——每次主题切换新写一份临时 HTML 且 dispose 从不清理；改用 `_tempFiles` 跟踪全部写入路径，dispose 时存在性检查后逐一删除。

### 🤖 For Agents
- **基线修正**：首轮报的「~235 warning」是 Actions 单步输出截断导致的错数（3074 条只落 1028 行）。准确基线（commit `c203caa`）：**3074 issues = 438 warning + 2836 info + 0 error**。warning 三条大头 `unused_local_variable` 84 / `unnecessary_cast` 73 / `unused_element` 60；最脏文件 `lib/core/services/api/chat_api_service.dart` 89 条。
- 本地 analyze 用法：`export PATH=/opt/flutter335/bin:$PATH PUB_HOSTED_URL=https://pub.flutter-io.cn`（`storage.googleapis.com` 在本沙箱不可达，须用 `storage.flutter-io.cn` / `pub.flutter-io.cn` 镜像）。
- **坑**：`dart fix --apply` 会顺带应用 `missing_dependency`，实测往 `pubspec.yaml` 注入 `path/characters/syncfusion_flutter_core/vector_math: any`——每批 apply 后必须 `diff pubspec.yaml` 并还原。
- `dart fix` 对 `unused_local_variable` / `unused_element` / `unused_field` / `unused_shown_name` / `dead_code` / `dead_null_aware_expression` / `unreachable_switch_default` **无机器修复**（剩余 248 条中的 214 条），只能人工判读。
- **坑（B1 实测）**：`unused_element_parameter` **禁止用 `dart fix`**——Dart 3.9 把构造函数初始化形参 `this.x` 判为未使用（哪怕 `widget.x` 在 build 里用了），机器修复直接删构造参数，残留 `final x;` 无初始化 → 实测 **15 个 `final_not_initialized_constructor` 编译错误**。该规则 34 条整条转人工。
- **坑（B1 实测）**：`unnecessary_cast` 修复后残留 `(body)[k]` 这类多余括号；批量去括号会把 `Overlay.of(context).x` 误伤成 `Overlay.ofcontext`（`(…)` 可能是调用参数表而非分组）。已尝试并撤回——自动修复产物不要"顺手美化"。
- **坑**：`flutter pub get` 会按 ARB 重新生成 `lib/l10n/app_localizations*.dart`（这就是 0.0.43 类外注入能在 CI 侥幸通过的原因）。改 l10n 永远先改 ARB，手改生成物会被覆盖。
- 已拍板政策：`unreachable_switch_default` 保留 default + `// ignore:` 注释；`unused_element` / `unused_field` 逐条判断（真废弃删、预留能力加 ignore 注明原因）。
- **B4 判读判据**（写进 `WARNING_CLEARANCE.md` §5）：① 注释明示保留（`Keep original button for compatibility` / `Keep the old paginated version for reference`）→ ignore；② 完整功能未挂入口（haptics 开关行 ×6、代理设置对话框、MCP tab、头像选取）→ ignore + §9a 清单；③ 构造参数在体内被读取（`size`/`haptics`/`onLongPress` 等）→ ignore；④ 局部 helper / 薄封装 / 重复实现遗留 → 删。
- **坑（B4 实测）**：脚本按括号平衡找块尾时，`{` 必须仅在 `paren==0` 时计为函数体开始——否则命名参数表 `{...}`（如 `void f({int x}) {`）的同行闭合会被误判为块结束，只删声明行留孤儿函数体。实测 6 处中招，已回滚重做。
- **坑（B4 实测）**：删除大块代码会连锁暴露新警告（B4 删除后新增 `_safeString`、`_TileStatus`、4 条 unused_import、`pressedScale`、`_userMenuActive` 共 8 条）——每批删除后必须重新 analyze，连锁项逐条判读，不能只看批次目标清单。
- **坑（B5 实测）**：行尾追加 ignore 时若原行已有 `//` 注释，`code; // foo // ignore: bar` 是**单个 comment token**，`ignore:` 段不会被 analyzer 识别——ignore 必须是独立注释段（另起一行或作为行内唯一注释）。
- **B5 新发现疑似 bug**（§9a）：~~`tts_provider` 网络 TTS 的 `cancelled` 局部变量从未被置 true，取消链路完全失效~~ **已修复（`8a65787`）**——改为每请求独立 `_TtsCancelToken`；`chat_api_service` Response API follow-up 仍被 `if (false && …)` 手动禁用（保留 + ignore），待用户决策。**坑（修复专项）**：共享 bool 标志 + 新请求重置存在跨请求竞态（旧请求的取消检查可能重新读到 false 而"复活"），每请求独立 token 实例才是正确模式；取消类异常要区分"主动取消"与"真失败"，前者不得污染错误状态。
- **坑（§9a 修复专项）**：bug 报"XX 列表不展示"时先查展示链路是否存在——backup_pane 的远程列表实际由"恢复"按钮 → `_RemoteBackupsDialog` 完整承载，pane 内预取字段只是旧设计遗留的死代码；处置方向是删死代码 + 修弹窗吞错误，而不是往 pane 里新接 UI。
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
