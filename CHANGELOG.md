# Changelog — MiniMe-Core

All notable changes to this project are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); versioning: `0.0.x` patch 递增，里程碑由用户拍板升 minor。

> 每个版本三档受众：**📣 For Users**（人话讲收益）/ **🔧 For Developers**（工程细节与迁移）/ **🤖 For Agents**（符号级变更 + 行为语义 + 坑位预警）。发布时同步 GitHub Release（用户档扩充版）与本文件（开发者档 + 模型档）。

## [0.0.55] - 2026-09-11

### 📣 For Users
- **对话流样式系统全量落地**：聊天界面终于能换风格了——一次性上架 15 种对话流样式（默认气泡 / 紧凑气泡 / 极简列表 / 卡片 / 双栏 / 杂志 / 代码优先 / 学术 / 禅意 / 弹幕 / 未来感 / 手账 / 商务 / 哥特 / 萌系），在设置页点开"对话样式"即可实时预览每一种样式长什么样，点一下立即生效，无需重启；
- **不懂选哪个？让 AI 帮你挑**：新增 StyleResolver 自动推荐——根据你日常对话长度、代码占比、阅读节奏，自动推荐最顺手的 3 种样式，点"推荐样式"一键应用；
- **所有样式共享同一份对话数据**：切换样式不会丢任何消息、不会重新排版历史、不会影响导出和搜索，样式只是"皮肤"，底层数据完全统一。

### 🔧 For Developers
- **Added**：
  - `lib/features/chat/style/`：对话流样式系统工程落地——可插拔 `StyleRenderer` 渲染策略接口，15 种样式各自实现一套 renderer，共享同一套 `MessagePart` 数据模型；
  - `ConversationDataSource` 统一数据进出口：所有样式经同一数据源读写消息，禁止样式直接操作底层存储；
  - `StyleResolver`：根据对话长度、代码块占比、消息密度等特征自动推荐样式，输出 top-N 候选；
  - 设置页新增"对话样式"预览入口：横向滑动预览卡片 + 一键应用 + 自动推荐按钮；
  - 样式渲染器数据访问约束 lint 规则纳入 `tools/me_bot_lints/`，防止样式绕过数据源直读存储。
- **Changed**：
  - 聊天消息渲染主链路从"固定气泡 widget"改为"按当前选中样式分发到对应 StyleRenderer"；
  - 版本号 `0.0.54+54` → `0.0.55+55`。

### 🤖 For Agents
- **新增样式**：实现 `StyleRenderer` 接口，在样式注册表登记 `(id, name, rendererFactory)`，样式内部只读 `MessagePart` 树，禁止直接访问数据库/prefs；
- **数据读写**：一律走 `ConversationDataSource`，样式层不得出现"绕过数据源直读存储"的代码，me_bot_lints 会拦；
- **自动推荐**：在 `StyleResolver` 扩特征维度时，新特征必须可解释（输出推荐理由给用户看），不要塞黑盒权重；
- **预览入口**：设置页预览走统一的预览卡片组件，不要为某个样式单独写预览页；
- **设计文档**：架构与扩展点见 `docs/design/conversation-style-system.md`（0.0.54 已落 v1.0，本版为工程实现落地）。

## [0.0.54] - 2026-09-11

### 📣 For Users
- **内置 MCP 三服务器架构定型**：MiniMe-Chat（网页抓取/对话增强）、MiniMe-Data（加密密钥派生与备份导入导出，共 8 个工具）、MiniMe-Code（代码能力占位，仅探测工具）三件套统一注册、按 id 精确连接，旧服务器自动迁移，无需用户手动重配；
- **安全中心一键修复不再误删配置**：此前"一键修复"会把已配好的供应商/搜索/TTS 当成旧数据清掉，本版彻底修掉——只清真明文残留，删前逐条确认并落备份，删完留审计；
- **日志层全量加固**：日志脱敏、轮转、导出、动态调级等 33 项问题一次性修完，现在可以一键把全部日志打包成 zip 分享给客服排查，且导出前已自动脱敏、不泄露密钥。

### 🔧 For Developers
- **Added**：
  - `tools/me_bot_lints/`：custom_lint 规则拆为独立本地包（v0.1.0，`publish_to: none`），承载 `no_empty_catch`/禁止 print/样式渲染器数据访问约束等规则；`pubspec.yaml` dev_dependencies 改为 `me_bot_lints: { path: tools/me_bot_lints }` 引用，主包只留入口；
  - `lib/core/services/logging/log_exporter.dart`（P3-32）：`LogExporter.exportLogs()` 先 `Logger.flush()` 再把全部 `.log` 打包 zip 到临时目录并记审计；Logger 写盘前已脱敏，导出不二次处理；
  - `Logger.setLevel(LogLevel)`（P3-33 铺垫）：运行时动态调整 `minLevel`，立即生效，切换本身以 info 留痕；
  - `LogTags` 扩充 8 个通道：`mcpConn`/`migration`/`network`/`theme`/`export`/`biometric`/`audit` 等，区分 MCP 连接生命周期与工具调用、安全事件与审计事件；
  - `docs/design/conversation-style-system.md`：对话流样式系统设计文档 v1.0——可插拔 `StyleRenderer` 渲染策略，15 种样式共享 `MessagePart` 数据模型，经 `ConversationDataSource` 统一读写，覆盖 Android/iOS/Desktop/Web。
- **Fixed**：
  - 日志层全量修复 33 项（P3-1 ~ P3-33）：覆盖 `api_logger`/`log_appender`/`log_sanitizer`/`logger` 等，补齐轮转、脱敏、缓冲 flush、空 catch 静默吞异常等问题；新增回归测试 `api_logger_trace_test.dart`/`log_rotation_test.dart`/`log_sanitizer_test.dart`；
  - 安全一键修复误删供应商 bug：白名单拦截 + v1→v2 迁移 + 删除前备份/审计/确认弹窗（延续 0.0.53 修复线，本版随包稳定发版）。
- **Changed**：
  - 内置 inmemory MCP 服务器统一收敛为 MiniMe-Chat / MiniMe-Data / MiniMe-Code 三服务器架构，旧 `minime_fetch` id 自动迁移；
  - 版本号 `0.0.53+53` → `0.0.54+54`。

### 🤖 For Agents
- **新增自定义 lint 规则**：一律落在 `tools/me_bot_lints/lib/src/` 并在 `me_bot_lints.dart` 注册，不要在主包 lib 里散落 custom_lint 实现；主包仅经 dev_dependency path 引用；
- **日志通道规范**：MCP 连接生命周期用 `LogTags.mcpConn`、工具调用用 `LogTags.mcp`；安全体检用 `LogTags.security`、审计事件用 `LogTags.audit`；新增模块先在 `LogTags` 登记常量再用，禁止裸字符串 tag；
- **运行时调日志级别**：用 `Logger.setLevel(...)`，不要直接改 `minLevel` 字段（无留痕）；调低到 warn/error 后切换点仍以 info 保留；
- **导出日志**：走 `LogExporter.exportLogs()`，不要自己遍历日志目录打包——漏 flush、漏脱敏、漏审计都是坑；
- **对话流样式**：新增样式实现 `StyleRenderer` 接口并经 `ConversationDataSource` 读写，禁止样式直接操作底层存储；详见 `docs/design/conversation-style-system.md`。

## [0.0.53] - 2026-09-11

### 📣 For Users
- **侧边栏历史对话大改版**：历史会话支持三种排序——自然顺序（按对话流）、按时间、按助手分类；支持拖拽直接调整顺序；同一助手的会话自动收进手风琴分组，展开/收起一键到位；侧边栏组件拆成 5 个，后续调样式不再牵一发动全身；
- **消息快捷按钮终于能点了**：之前聊天消息下方的翻译、更多等快捷按钮偶尔点了没反应，根因是图标按钮的手势行为冲突，已彻底修复；翻译过程中也有明确的加载状态，不会再像卡死；
- **界面标题全面统一**：全仓 24 个文件的卡片/页面标题统一换成新组件，卡内标题居中、左右边距终于一致，不再有的偏左有的偏右；
- **安全中心一键修复不再误删配置**：此前"一键修复"会把你辛苦配好的供应商、搜索、TTS 当成旧数据一起清掉，本版彻底修掉——现在只会清真正的明文残留，删之前逐条告诉你要删什么，删完还留备份；
- **内置 MCP 服务器升级**：原内置网页抓取服务器更名为 MiniMe-Chat（功能不变）；新增 MiniMe-Data，提供加密密钥派生/加解密/密钥健康查询 + 备份导入导出/校验/列备份共 8 个工具；另新增占位服务器 MiniMe-Code，为后续代码能力预留。

### 🔧 For Developers
- **Added**：
  - `lib/shared/widgets/app_section_header.dart`：`AppSectionHeader` 统一标题组件，全仓 24 个文件迁移，卡内标题居中与边距问题一并收敛；
  - `lib/core/services/mcp/inmemory_transport.dart`：`InMemoryMcpServer` 抽象接口 + 通用 `InMemoryClientTransport`，microtask 异步转发，对齐真实 network transport 语义；
  - `lib/core/services/mcp/jsonrpc_engine_base.dart`：`BaseJsonRpcMcpEngine` 封装 initialize/tools-list/tools-call 与 `_ok`/`_error`/`_noop` 响应样板；
  - `lib/core/services/mcp/minime_data/`：新建内置 MiniMe-Data 服务器，8 个工具——加密密钥 4 个（`derive_key`/`encrypt`/`decrypt`/`key_health`）+ 备份导入导出 4 个（`export_backup`/`import_backup`/`verify_backup`/`list_backups`），加密复用 `BackupEncryptor`，凭证桥接复用 `BackupCredentialBridge`；
  - `lib/core/services/mcp/minime_code/`：占位服务器，仅 `ping`/`version` 两个探测工具；
  - 侧边栏排序：`ConversationSortMode` 自然/时间/助手三模式 + 拖拽排序 + 手风琴分组，拆为 5 个组件；
  - 安全修复测试：`test/core/services/security/legacy_prefs_scanner_test.dart`（白名单拦截回归）、`test/core/providers/settings_provider_migration_test.dart`（v1→v2 迁移三分支）。
- **Fixed**：
  - 消息快捷按钮（翻译/更多）点击无响应：根因 `IosIconButton` 手势行为冲突，统一改为正确的点击手势；翻译按钮补加载态；全仓同类点击穿透问题 3 处一并加固（长按菜单、其他按钮等）；
  - 安全 P0（误删供应商）：`legacy_prefs_scanner._legacyKeyNames` 只保留真正可删的纯明文残留（全局代理用户名/密码）；新增 `_activeKeysWhitelist` 双保险——`autoFix` 删除前命中白名单一律拒绝并记 error 审计，即使未来有人误把 active key 加回删除清单也不会再丢数据；
  - 安全 P1（换 key 迁移）：`provider_configs`/`search_services`/`tts_services` 三个配置 key 从 v1 切到 v2 命名空间；`SettingsProvider.migrateLegacyV1Keys(prefs)` 启动期把 v1 内容搬到 v2 并清 v1，三个 key 独立迁移、单失败只 warn；`tts_provider._readTtsServicesRaw` v2 缺失兜底读 v1 并就地搬 v2；`cherry_importer`/`data_sync` 备份导入时 v1→v2 键名归一；
  - 安全 P2：`autoFix` 删除前把待删 key 当前值备份到 `<文档目录>/security_backups/autofix_<ts>.json`；逐条 `CredentialAuditLogger` 审计（`autoFixDelete`/`autoFixComplete`，不带值）；安全页一键修复确认弹窗逐条列出 `finding.title` + `detail`（截断 120 字）。
- **Changed**：
  - 旧内置 `minime_fetch`（旧名 `@minime-core/fetch`）更名为 `minime_chat`（显示名 MiniMe-Chat），`mcp_provider` 启动时自动迁移旧 id 与旧品牌名；三个内置服务器元数据集中在 `_builtinServers` 维护，按 id 精确匹配，不再用 `transport==inmemory` 模糊判断；`connect` 时按 `server.id` 分发到对应引擎（`_createInMemoryEngine`）；
  - 版本号 `0.0.52+52` → `0.0.53+53`。
- **Removed**：
  - 旧 `lib/core/services/mcp/minime_fetch/` 目录（inmemory + server），功能迁入 `minime_chat/`。

### 🤖 For Agents
- **内置 inmemory MCP 服务器新增流程**：在 `mcp_provider._builtinServers` 登记 `(id, name)`，在 `_createInMemoryEngine` 追加 `case` 分支返回对应引擎；引擎继承 `BaseJsonRpcMcpEngine`，只实现 `serverName`/`serverVersion`/`toolDefinitions`/`callTool`，不要自己写 transport；
- **旧 id 迁移**：`minime_fetch` → `minime_chat` 在 `_migrateLegacyFetchId` 兜底；新增内置服务器不要复用旧 id，也不要用 `transport==inmemory` 做模糊识别，一律按 id 精确匹配；
- **prefs 配置 key 命名空间已切 v2**：业务代码一律读写 `*_v2`；v1 副本只在迁移窗口期存在，`SettingsProvider._load` 第一步就是 `migrateLegacyV1Keys`，任何在它之前读 v1 的代码都是错的；新增配置 key 直接用 `_v2` 后缀，不要再开 `_v1`；
- **安全一键修复红线**：`_legacyKeyNames` 里只能放"凭证已搬进安全存储、prefs 副本无任何业务读取路径"的 key；仍在使用的配置 key 即使以 `_v1` 结尾也绝不能删——它们已进 `_activeKeysWhitelist`，删除会被白名单拦截并记 `autoFixBlocked`；
- **删除 prefs key 的标准姿势**：先 `_backupBeforeDeleting` 落备份 JSON，再逐条 `CredentialAuditLogger.record('autoFixDelete', ...)`，备份失败只 warn 不阻断；
- **快捷按钮点击穿透**：消息流内可点击元素统一走已修复的手势行为，不要再包裸 `GestureDetector`/`IosIconButton`；翻译类异步操作必须有加载态；
- **侧边栏排序**：`ConversationSortMode` 三值（natural/time/assistant），拖拽顺序持久化在 provider，手风琴折叠状态独立；新增排序模式先扩枚举再补分组器。

## [0.0.52] - 2026-09-10

### 📣 For Users
- **统计页面大升级**：数据更准了——会话数只统计有实际消息的会话、模型和助手排行按 token 用量排序；新增周期对比（环比上周期涨跌幅）、CSV 数据导出、热力图点击查看当天详情、趋势图悬停显示明细；加载时有骨架屏，数字切换有平滑动画；
- **安全中心全面增强**：新增安全评分仪表盘（0-100 分，点击看扣分明细）；体检项支持单个修复（之前一键修复会误修全部）；清除审计日志现在需要生物识别验证；密钥健康显示配置名和轮换倒计时；隐私门禁显示生物识别状态和剩余宽限时间；白名单策略新增冲突检测（命令不在白名单时警告并一键添加）；安全事件改为时间线视图，支持筛选和分页加载；
- **弹窗体验统一**：全仓确认弹窗、通知弹窗、输入弹窗统一为新的共享组件，视觉和交互一致；新页面强制使用共享组件构建，后续不会再出现风格割裂的弹窗。

### 🔧 For Developers
- **Added**：
  - `lib/shared/widgets/app_dialog.dart`：`AppDialog` 统一弹窗组件——`confirm`（确认/危险确认）、`alert`（通知）、`input`（文本输入）、`progress`（进度加载）四种模式，统一圆角/颜色 token/动画；
  - `tools/l10n_lints/lib/l10n_lints.dart` 新增 3 条强制执行 lint：`no_raw_alert_dialog`（禁止裸 AlertDialog/Dialog）、`no_manual_listview_padding`（禁止页面手写 ListView padding）、`no_scrollable_false`（禁止 `AppPage(scrollable:false)` 必须用 `AppPage.selfScrolling`）；
  - 统计页面：`StatsSkeleton` 骨架屏、`AnimatedNumber` 数字动画、周期对比 `StatsSnapshot.previous`、CSV 导出、热力图 AppSheet 详情；
  - 安全页面：7 个 widget 文件拆分（`security_shared` / `security_score_card` / `security_checkup_section` / `security_key_health_section` / `security_app_lock_section` / `security_policy_section` / `security_audit_section`）；
  - 安全服务层：`KeyHealthInfo.rotationDaysRemaining` 倒计时计算、`LocalPolicyProvider` 正则校验、`SecurityCheckupService` 每扫描器 10 秒超时。
- **Fixed**：
  - 统计 P0：`conversationCount` 从按会话 createdAt 过滤改为遍历窗口内消息按 conversationId 去重；模型/助手排行从按消息条数改为按 token 聚合降序；
  - 统计 P1：`launchCount` 按天过滤（`app_launch_dates` 按日去重）；`StatsSnapshot.compute` 移至后台 isolate（Hive 对象 detach 后跨 isolate）；
  - 安全 P0：单 finding 修复按钮（原 `onTap:_autoFix` 修复全部 → `onFixSingle(f)` 只修当前项）；清除审计日志增加 `AppLockService.verifyWith` 生物识别验证；
  - 安全 P1：密钥健康显示配置名（`providerConfigs[name]?.name ?? providerId`）；`_buildService` 缓存到 `_cachedService`；`_lockFuture`/`_policyFuture` 在 initState 创建避免重复 build；MCP 服务器关闭时弹危险确认；
  - 安全 P2：审计日志分页（硬编码 12 → 可扩展 limit + 加载更多）；`listSync()` → `list().toList()` 异步；添加命令/主机重复提示；`allowHttp` 开启时风险警告；`lockNow` 后清空解锁态强制重验证；
  - 安全 P3：自动修复记录每条 finding 的 title/severity 到审计 detail；`markRotated` 失败也记录审计。
- **Changed**：
  - 全仓迁移：约 80 处 `AlertDialog`/`Dialog`/`SimpleDialog` → `AppDialog`；约 17 处 `ListView(padding:)` → `AppListView`；涉及 44 个文件；
  - `security_page.dart`：912 行单文件 → 388 行薄壳 + 7 个 section widget；
  - 版本号 `0.0.51+51` → `0.0.52+52`。
- **Tests**：
  - 统计：`test/stats/stats_aggregator_test.dart`（24 个）+ `test/stats/stats_window_test.dart`（6 个），共 30 个全部通过；
  - 安全：`test/core/services/security/key_health_test.dart`（+6 倒计时）+ `policy_test.dart`（+6 正则）+ `security_score_test.dart`（新建 11 个评分），安全模块共 81 个全部通过。

### 🤖 For Agents
- **新页面强制执行规则**（custom_lint，CI 硬门禁）：
  - 禁止裸 `AlertDialog(` / `Dialog(` / `SimpleDialog(` → 必须用 `AppDialog.confirm/alert/input/progress`；
  - 禁止页面级 `ListView(padding:)` → 必须用 `AppListView` / `AppListViewBuilder`（水平 padding 固化 16 不可覆盖）；
  - 禁止 `AppPage(scrollable: false)` → 必须用 `AppPage.selfScrolling`（自动 `bodyPadding:zero`）；
  - 豁免：行尾加 `// ignore: no_raw_alert_dialog 白名单：<原因>`，仅限桌面端固定尺寸复杂窗口（JSON 编辑器/MCP 编辑表单/HTML 预览等）、聊天流 padding=0、下拉浮层内 shrinkWrap 列表等合理场景；
- `AppDialog` API：`AppDialog.confirm(context, {title, message, confirmText, cancelText, danger})` / `AppDialog.alert(context, {title, message})` / `AppDialog.input(context, {title, hintText, initialValue, confirmText, cancelText})` / `AppDialog.progress(context, {title, message})` 返回 `Future<bool>` / `Future<String?>`；
- 统计 `StatsSnapshot.compute(report, window, launchDates)` 必须传 `launchDates` 否则启动次数不过滤（UI 层标注 `(all)`）；`StatsSnapshot.previous` 自动计算上一周期，总览格显示环比百分比；
- 安全 section 组件均为纯展示 widget，状态和回调由 `SecurityBody` 父级持有；新增安全功能优先在对应 section 文件中扩展，不要把逻辑塞回 `security_page.dart`；
- 安全评分 `SecurityScoreResult.compute({report, health, lockEnabled, allowlistEnabled})` 0-100 分，4 级颜色（≥85 优秀/≥70 良好/≥50 一般/<50 危险），扣分明细可展开；
- 全仓仍有 13 个文件保留 `no_raw_alert_dialog` 白名单（桌面端复杂独立窗口）、5 个保留 `no_manual_listview_padding`（聊天流/浮层列表）、5 个保留 `no_scrollable_false`（TabBarView/空态页面），均为预审计合理例外，新增页面不得效仿。

## [0.0.51] - 2026-09-10

### 📣 For Users
- **安全中心卡片宽度修复**：安全页面的卡片之前比其他设置页偏窄（左右留白过大），现已与设置、备份等页面完全对齐；
- **日志查看页同步修复**：日志页面存在同样的卡片过窄问题，本版一并修复；
- **页面宽度统一保障**：新增统一的滚动列表容器，后续新页面的卡片宽度会自动保持一致，不再出现个别页面偏窄的情况。

### 🔧 For Developers
- **Added**：
  - `lib/shared/widgets/app_list_view.dart`：`AppListView` / `AppListViewBuilder` 共享组件——水平 padding 固定 `AppGap.md`(16) 不允许覆盖，垂直 padding 有默认值（top 12 / bottom 16）可通过 `topPadding` / `bottomPadding` 配置；
  - `AppPage.selfScrolling` 命名构造函数——自动设置 `scrollable: false` + `bodyPadding: AppPagePadding.zero`，语义化 API 杜绝漏配；
- **Fixed**：
  - `security_page.dart`：原 `AppPage(scrollable:false)` 未传 `bodyPadding:zero`，与内部 `ListView(padding:16)` 叠加成双层水平内边距（16+16=32px/侧），改为 `AppPage.selfScrolling` + `AppListView`；
  - `log_viewer_page.dart`：同样的双层 padding 问题，改为 `AppPage.selfScrolling`；
- **Changed**：
  - 版本号 `0.0.50+50` → `0.0.51+51`。

### 🤖 For Agents
- **内部自带滚动容器的页面必须用 `AppPage.selfScrolling`**，禁止再写 `AppPage(scrollable: false)` 而漏配 `bodyPadding: zero`——这是双层 padding 的唯一根因；
- **列表容器用 `AppListView`**，水平 padding 已固化为 16，不允许页面自行覆盖；垂直 padding 仅在底部有悬浮按钮等特殊场景下调大 `bottomPadding`；
- `AppPage.selfScrolling` 与默认 `AppPage` 的区别：前者 `scrollable=false + bodyPadding=zero`，后者 `scrollable=true + bodyPadding=hv(16,12)`；body 内部无滚动时用默认构造函数，body 内部有 ListView/ReorderableListView 时用 `selfScrolling`；
- 全仓仍有约 13 个 `scrollable: false` 的页面未迁移到 `selfScrolling`，后续逐步替换（已迁移：security / log_viewer）。

## [0.0.50] - 2026-09-10

### 📣 For Users
- **全新应用图标**：Android（含自适应圆角）、iOS、Web、Windows、macOS 全平台图标统一替换，视觉一致；
- **安全中心边距对齐**：修复安全页卡片/小节标题在宽屏下与其它设置页的边距、宽度不一致的问题，现在整页对齐统一设计；
- **文档重做**：README 重构为规范技术文档（功能矩阵、架构分层、快速上手），支持中英双语；
- 仓库内部结构整理（不影响你手上的产物）。

### 🔧 For Developers
- **Added**：
  - `assets/app_icon.png`（1252×1252）由用户提供的原图（WEBP）仅做格式转换生成，作为唯一图标源；统一 `pubspec.yaml` 的 `flutter_launcher_icons:` 段（`image_path` / `adaptive_icon_foreground` 均指向 `assets/app_icon.png`，`remove_alpha_ios: false`）；
- **Changed**：
  - `lib/features/security/pages/security_page.dart`：小节标题/描述 `EdgeInsets.fromLTRB(2, …)` 游离字面量 → `AppGap.sm`（回归设计 token，与 backup / storage / settings 页对齐）；
  - `lib/desktop/desktop_settings_page.dart`：桌面端安全 pane 嵌入 `SecurityBody` 处补 `Container(alignment: topCenter) + ConstrainedBox(maxWidth: 960)`，与 TTS / 搜索 / 备份等桌面设置 pane 完全一致（宽屏居中、窄屏对齐）；
  - README 双语重写：移除商店徽章 / 应用图片 / 示例截图（`docx/` 示例图文件夹已删除），结构按标准文档规范（Overview / Features / 平台表 / Documentation / Architecture / Project Structure / Getting Started）；
  - 仓库清理：删除构建产物与临时文件（`build/`、`.dart_tool/`、`.trae-html-share-packages/`、`android/.gradle/`、`android/local.properties`、`pubspec.lock`、`devtools_options.yaml`、`l10n_untranslated.txt` 等），文档归层为 `docs/architecture/`、`docs/design/`、`docs/versioning.md`；
- **Removed**：
  - 旧图标变体 `assets/app_icon_2.png` / `app_icon_dark.png` / `app_icon_macos.png` / `app_icon_macos2.png` / `app_icon_foreground.png`；顶层 `flutter_launcher_icons.yaml`；`docx/` 示例图文件夹。

### 🤖 For Agents
- 图标唯一源 = `assets/app_icon.png`；`pubspec.yaml` 的 `flutter_launcher_icons:` 段已统一指向它（`image_path` / `adaptive_icon_foreground` 均用该路径，`remove_alpha_ios: false`，iOS 不生成 dark 变体）；改图标只动 `assets/app_icon.png` 后跑 `flutter pub run flutter_launcher_icons`；
- 小节标题横向缩进必须用语义 token：安全页已用 `AppGap.sm`，新增页面禁止再用字面量 `2`（属设计 token 红线）；
- 桌面端设置 pane 嵌入子页面 body 时，必须包 `Container(alignment: topCenter) + ConstrainedBox(maxWidth: 960)`（参考 `desktop_settings_page.dart` 的 TTS / 搜索 / 备份 / 安全，统一宽屏居中），否则宽屏下卡片铺满全宽、与别的页宽度不一致；
- `pubspec.lock`、`build/`、`.dart_tool/`、`.trae-html-share-packages/`、`android/.gradle/`、`android/local.properties`、`devtools_options.yaml`、`l10n_untranslated.txt` 等**不入库**（已加 `.gitignore`）；`dependencies/flutter_tts/` 是 `path:` 构建必需源码依赖，**必须保留**；
- 文档分层：架构审计 → `docs/architecture/overview.md` + `action-items.md`；设计类 → `docs/design/*`；版本规范 → `docs/versioning.md`；跨文档引用已更新，移动文件须同步改链接。

## [0.0.49] - 2026-09-10

### 📣 For Users
- **界面风格全面统一（告别割裂感）**：
  - 安全中心页整页重排：与设置、备份等页面一致的 iOS 分组卡片风格——体检、密钥健康、门禁、白名单、安全事件五段统一呈现；
  - 桌面端设置里的安全页不再出现双层标题栏；
  - 备份、存储、字体选择、日志查看、助手编辑等页面同步对齐：统一行高、图标、开关与触感；
  - 所有操作提示统一为顶部浮层（成功/失败/警示各有颜色语义），不再出现底部黑条。

### 🔧 For Developers
- **Added**：
  - 设计系统守护 lint 三条（error 级，CI fatal）：`no_raw_scaffold`（页面壳必须 AppPage，全屏特例走文件级白名单注释）、`no_material_snackbar`（通知必须 showAppSnackBar）、`no_material_list_tile`（列表行必须 AppNavRow/AppSwitchRow）；
  - CI custom_lint 转 fatal：`dart run custom_lint --no-fatal-infos --no-fatal-warnings`（仅 ERROR 阻塞，存量 warning 继续报告）；
  - `docs/design/design-system.md`：组件映射表 + 新页面 checklist + 豁免机制；
  - 设计令牌 `AppStatusColor`（success/danger/warning，iOS 系统色板，与通知体系同源）。
- **Changed**：
  - `security_page` 双端拆壳：`SecurityPage` 移动薄壳（AppPage）+ `SecurityBody` 纯 body（桌面设置 pane 直接嵌入）；802 行手写 Material 风格全部映射为设计系统组件；
  - 10 文件 SnackBar→showAppSnackBar（backup / storage×5 / model_edit_dialog / webview）、3 文件 ListTile→AppNavRow（google_fonts / log_settings_sheet / backup_pane）、log_viewer 与 assistant_settings_edit 裸 Scaffold→AppPage 壳；
  - 5 个全屏特例（home / image_viewer / qr_scan / html_preview / webview）登记 no_raw_scaffold 白名单注释；
  - snackbar 语义色改引 AppStatusColor（单一事实来源）。
- **Fixed**：
  - 桌面端设置→安全 pane 双层标题栏（整页嵌入改为 body 嵌入）；
  - v0.0.48 发版时 pubspec 版本号未随 tag 入库的遗留（本版直接 bump 0.0.49+49）。

### 🤖 For Agents
- `Scaffold` / `SnackBar` / `ListTile` 在 lib/ 下现为 **error 级 lint 违规**（`no_raw_scaffold` / `no_material_snackbar` / `no_material_list_tile`），生成代码必须走 `AppPage` / `showAppSnackBar` / `AppNavRow`+`AppSwitchRow`；
- 全屏特例豁免 = 文件内注释含「no_raw_scaffold 白名单」（home / image_viewer / qr_scan / html_preview / webview 五文件已登记，规则检测该标记整文件豁免）；
- 语义色常量 `AppStatusColor.success/danger/warning`（0xFF34C759 / 0xFFFF3B30 / 0xFFFF9500），`Colors.green/red/amber` 不再允许散落；
- CI 静态分析步 custom_lint 退出非 0 即禁止合并（error 级规则触发时）。

## [0.0.48] - 2026-09-10

### 📣 For Users
- **安全中心全面强化**：
  - 门禁开关更严谨：开启与关闭都需现场验证，防止他人随手关掉让保护形同虚设；
  - 解锁更省心：验证成功后默认 5 分钟内（可选 0/1/5/15）再次查看无需重复验证，验证失败不进入宽限期；
  - 新增「最近安全事件」：查看/复制密钥、口令输入、迁移、修复、标记轮换等操作留痕（本机保存，可复制/导出/清空）；
  - 白名单从只读升级为可管理：MCP 命令白名单支持增删与恢复默认（正则校验），例外网站可增删，MCP 服务器逐个开关；
  - 密钥健康增强：条目点击直达服务商编辑页，支持一键「标记已轮换」；
- **界面语言大扫除**：
  - 修复 60+ 处界面文案在英文等语言下的漏译（安全体检、用量统计、存储管理、翻译页、服务商推广卡等全量补齐）；
  - 繁体中文全面对齐台湾常用语（金鑰/伺服器/資料/點擊/列印…），简繁切换更自然；
  - 界面文案新增"防漏译闸门"：以后新增页面的文案漏译会在写代码与构建时被直接拦下。

### 🔧 For Developers
- **Added**：
  - `BuildContextL10n` extension（`context.l10n` 非空快捷入口；`l10n.yaml` 开 `nullable-getter: false`）；
  - `CheckupStrings` 注入接口：scanner 层文案与 l10n 解耦，新增扫描器文案由编译错误驱动补齐；
  - custom_lint 插件 `tools/l10n_lints`（analyzer 6.x API）：`hardcoded_ui_string`（UI 中文字面量拦截，白名单参数名 + CJK 正则）、`l10n_no_field_cache`（AppLocalizations 字段缓存拦截）；
  - 护栏 `tools/check_l10n.py`：R1 三语键集一致 / R2 带参必有 meta / R3 死占位符 / R4 驼峰命名 / R5 死键 / R6 空翻译（error 阻断，R4/R5 仅告警）；
  - `tools/sync_l10n.sh`（护栏+gen 一条龙）、`tools/watch_l10n.sh`（inotify 监听 arb 自动 gen，无 inotify 时轮询降级）；死键存量留档 `tools/l10n_dead_keys.txt`。
- **Changed**：
  - zh_Hans 出库：arb 三份（en/zh/zh_Hant），繁体经 OpenCC `s2twp` 生成后人工校词；`supportedLocales` 收窄 `[en, zh, zh_Hant]`；
  - 546 处 `AppLocalizations.of(ctx)!` 全量替换为 `ctx.l10n`（按捕获变量名机械替换 + analyze 清理 unused import）；
  - `StatsL10n` 可空包装层拆除（nullable 时代 `?. ?? 中文兜底` 全部消亡，36 getter 直接映射 arb 键）；
  - arb +27 键（checkup 文案 14 + 推广卡/翻译页/SnackBar/重试 13）、-1 死键（statsNoActivity）。
- **Hardening**（安全中心强化包）：`AppLockService` 开关双向验证 + 解锁宽限期（`graceChoices` 0/1/5/15 分钟，失败不刷新、管理动作不留宽限）+ `load(verifier)` 注入 + 认证异常兜底；`CredentialAuditLogger`（ring buffer 100 + SharedPreferences 持久化 + recent/clear）；`KeyHealthService.markRotated`；`SecurityPage` 五段重写（体检自动跑+修复确认+fixHint / 健康+标记轮换 / 门禁宽限期 / 白名单 chips / 最近安全事件）。
- **CI**：5 个构建 job 在 Inject fallback 后前置 `flutter gen-l10n`（gen 产物不入库，路径进 `.gitignore`）；Android 门禁追加 `check_l10n.py` + `custom_lint`（当前 report-only，硬编码清零后转 fatal）。
- **Verified**：`flutter analyze` 0 error/0 warning；custom_lint 0 issue（29→0）；护栏 PASS（144 warn 为存量死键告警）；`flutter test` 154 用例全绿。

### 🤖 For Agents
- **行为语义**：`AppLocalizations.of` 返回**非空**——键不存在=编译错误（第一道闸门），不存在"运行时兜底文案"这回事；统一入口 `context.l10n`（`lib/l10n/build_context_l10n.dart`），**禁止**再写 `AppLocalizations.of(context)!`；`supportedLocales=[en, zh, zh_Hant]`：zh_Hans 设备经 gen 代码 languageCode 兜底自动落到 zh（零感知），zh_TW/HK/MO 由 framework 特判进 zh_Hant。
- **新增文案流程（必经）**：①三份 arb 同步加键（en 带参必须带 `@key.placeholders`）→ ②`flutter gen-l10n`（或开着 `watch_l10n.sh`）→ ③代码用 `context.l10n.key`。漏做会被两端拦截：写码时 custom_lint 红线、CI 门禁护栏 R1/R2。core/services 层**禁止**直接依赖 AppLocalizations——scanner 类走 `CheckupStrings` 注入，服务层日志与异常文本**永不**进 arb。
- **坑位预警**：
  ① `// ignore: l10n_no_field_cache` 行内追加中文说明（如 `—— 注释`）会让 analyzer 忽略解析整条 ignore，必须单独成行（实测踩过）；
  ② gen 产物（`lib/l10n/app_localizations*.dart`）不入库、手改必被覆盖，CI 每次构建前重新生成；
  ③ 无 l10n delegates 的裸 widget 测试里 `context.l10n` 直接抛非空断言——wrap 需带 `AppLocalizations.localizationsDelegates` + `locale: Locale('zh')`（断言中文文案时 locale 缺省是 en，实测踩过）；
  ④ `dynamic context` 上调 `context.l10n` 编译不报错但运行时必崩（extension 不参与动态分发）——参数类型必须显式 `BuildContext`（assistant_provider 实测踩过）；
  ⑤ `List<String>` 不能作 arb 占位符类型，列表参数在注入层 `join(', ')` 后传 String；
  ⑥ 存量死键 142 条见 `tools/l10n_dead_keys.txt`（R5 仅告警），清理排期后续版本。

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
- **Added**：`docs/design/warning-clearance.md`——438 warning 清零批次计划（B0–B6）、进度看板、红线。
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
- **B4 判读判据**（写进 `docs/design/warning-clearance.md` §5）：① 注释明示保留（`Keep original button for compatibility` / `Keep the old paginated version for reference`）→ ignore；② 完整功能未挂入口（haptics 开关行 ×6、代理设置对话框、MCP tab、头像选取）→ ignore + §9a 清单；③ 构造参数在体内被读取（`size`/`haptics`/`onLongPress` 等）→ ignore；④ 局部 helper / 薄封装 / 重复实现遗留 → 删。
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
