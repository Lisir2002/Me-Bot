# Warning 清零规划（MiniMe-Core）

> 目标：把 `flutter analyze` 的 **warning 从 438 清零**，为 `flutter analyze --no-fatal-infos` 硬门禁铺路。
> 状态：规划已批准待执行；基线实测于 2026-09-08，commit `c203caa`。
> 本文件是执行手册，不是讨论记录；每完成一批必须回来更新 §7 进度看板。

---

## 1. 基线（实测，非估算）

| 项 | 值 |
|---|---|
| 总 issues | 3074（info 2836 / warning 438 / error **0**） |
| warning 数 | **438**，分布 85 个文件、19 条规则 |
| 目录分布 | `lib/features` 189 · `lib/core` 141 · `lib/desktop` 95 · `lib/shared` 7 · `lib/utils` 4 · `lib/main.dart` 2 |
| 最脏文件 | `chat_api_service.dart` 89 · `desktop_settings_page.dart` 44 · `assistant_settings_edit_page.dart` 39 · `home_page.dart` 28 · `mcp_provider.dart` 19 · `chat_input_bar.dart` 16 |

**为什么基线是 438 而不是首轮报的 235**：首轮 CI 输出被 GitHub Actions 单步截断（3074 条只落了 1028 行明细）。已把 CI 步骤改为 `flutter analyze | grep -v "info •"`，拿到完整 438 行清单（`/tmp/ci_warn.txt`）。**以后任何"基线数字"都必须在无截断前提下重新统计。**

---

## 2. 关键前提：本地分析环境已打通（推翻 AGENTS.md §1 旧结论）

| 项 | 说明 |
|---|---|
| SDK | `/opt/flutter335`（Flutter **3.35.7** / Dart **3.9.2**），与 CI `FLUTTER_VERSION: '3.35.7'` 完全对齐 |
| 下载源 | `https://storage.flutter-io.cn`（storage.googleapis.com 在本沙箱不可达） |
| pub 源 | `PUB_HOSTED_URL=https://pub.flutter-io.cn`；`pub get` 约 18s |
| 全量 analyze | **约 48s**（冷）/ 8s（热），结果与 CI **逐条一致（438/438）** |
| 用法 | `export PATH=/opt/flutter335/bin:$PATH PUB_HOSTED_URL=https://pub.flutter-io.cn` |

**这把验证成本从"每批等 11 分钟 CI"降到"每批 48 秒本地"**，因此本规划才能做到分批小步、每批必验。
本地副本建议放 `/root/.codebuddy/artifact/warn-sb/Me-Bot`（不含 `.git`），工作区保持干净，验证通过后再把改动搬回 `/workspace/Me-Bot`。

> ⚠️ 本地**只用于 analyze**。`build` 仍未验证（Android SDK/签名等未就位），发版产物继续走 CI。

---

## 3. 三档风险分类（含实测可自动化量）

| 档 | 规则 | 条数 | 处置 | 可自动 |
|---|---|---:|---|---:|
| **A 机械** | `unnecessary_cast` | 73 | 删 `as T`（类型已推断，纯语法级） | ✅ 73 |
| | `unused_import` / `duplicate_import` | 31 / 7 | 删导入 | ✅ 38 |
| | ~~`unused_element_parameter`~~ | 34 | **已撤出自动化**：Dart 3.9 对初始化形参 `this.x` 是误报，机器修复会删构造参数（§6 红线 7） | ❌ |
| | `unused_catch_stack` / `unused_catch_clause` | 3 / 2 | 删 `catch (e, st)` 的 st / 整句 | ✅ 5 |
| | `unnecessary_non_null_assertion` | 35 | 删 `!`（接收者已非空，`!` 本就是 no-op） | ✅ 35 |
| | `invalid_null_aware_operator` | 18 | `a?.b` → `a.b` | ✅ 18 |
| | `unnecessary_null_comparison` | 17 | 删恒真判空 | ✅ 17 |
| | `unnecessary_type_check` | 6 | 删恒真 `is` | ✅ 5 |
| | `unnecessary_question_mark` | 1 | 删多余 `?` | ✅ 1 |
| **B 判读** | `unused_local_variable` | 84 | 删声明 or 保留（初始化有副作用则只删变量名、留表达式） | ❌ |
| | `unused_element` | 60 | 删 or 加 `// ignore: unused_element` 注明预留 | ❌ |
| | `unused_field` | 23 | 删 or 保留（JSON/序列化/预留） | ❌ |
| | `unused_shown_name` | 4 | 从 `show` 列表移除 | ❌ |
| | `unused_element_parameter` | 34 | 多数为误报（初始化形参），逐条判断：加 ignore / 改 `_` / 删 | ❌ |
| **C 语义** | `dead_null_aware_expression` | 19 | `a ?? b` 中 b 永不执行——**先确认 b 无副作用**再删 | ❌ |
| | `unreachable_switch_default` | 14 | 防御性 default：倾向保留 + ignore（见 §5 决策） | ❌ |
| | `dead_code` | 6 | 删恒假分支 | ❌ |
| | `invalid_use_of_protected_member` | 1 | 重构调用点 | ❌ |

**B1 实测（已落盘）**：对 A 档 10 条规则执行 `dart fix --apply`，**438 → 248（消 190 条）**，error 0。
`unused_element_parameter` 原计划一并自动修复，实测引入 15 个 `final_not_initialized_constructor` 错误，已整条撤出（见 §6 红线 7）。

---

## 4. 批次计划

| 批次 | 内容 | 条数 | 手法 | 预期剩余 |
|---|---|---:|---|---:|
| **B0** | 环境打通 + 基线锁定 + 推演 | — | 装 SDK / 对齐 CI / 副本实测 | 438 |
| **B1** | A 档 10 条规则 | 190 | `dart fix --apply --code=…` 逐规则执行 | **248** ✅ |
| **B2** | `unused_shown_name` + `unused_field` | 27 | 脚本 + 逐条确认 | 221 |
| **B3** | `unused_local_variable` | 84 | **逐条人眼判读**（副作用风险） | 137 |
| **B4** | `unused_element` + `unused_element_parameter` | 93 | 逐条判读，区分"真废弃 / 预留 API / 误报" | **44** ✅（43 C档 + 1 保留字段）|
| **B5** | C 档全部 | 43 | 逐条判读 + 少量重构 | **0** ✅ 清零达成 |
| **B6** | 门禁硬化 | — | CI 改 `--no-fatal-infos` | 0 |

**执行顺序原则**：先横扫 A 档（收益最大、风险最低、可逆），再按"文件聚集"纵切 B/C 档——同一文件的问题一次改完，diff 集中易 review，避免同一文件被反复改动。

每个批次的固定动作：
1. 副本执行 → 2. 本地 `flutter analyze`（warning 数必须单调下降、error 必须 0）→ 3. 把改动搬回工作区 → 4. commit（一个批次一个 commit，message 注明批次与条数）→ 5. push → 6. CI 观察步骤复核 → 7. 更新 §7 看板。

---

## 5. 已拍板的处置政策（2026-09-09 用户确认）

| # | 议题 | 结论 |
|---|---|---|
| P1 | `unreachable_switch_default`（14） | **保留 default + `// ignore: unreachable_switch_default`**，注释写明"防御未来新增枚举值" |
| P2 | `unused_element` / `unused_field`（83） | **逐条判断**：真废弃的删；确属预留能力的加 `// ignore:` 并注明原因 |
| P3 | B1 落地方式 | **直接落 + 本地验证 + push**，push 前贴改动清单 |

---

**B4 判读判据（已执行）**：93 条逐条判读的处置规则——
1. **删除**（56 条）：局部 helper 闭包、一行薄封装、重复实现遗留（`_mapDeviceLocaleToSupportedTag` vs `_localeToTag`）、注释标明旧版但无保留价值的 UI 件、体内无读取的纯可选参数。
2. **保留 + ignore**（37 条）：① 注释明示保留（`Keep original button for compatibility` 的 `_CircleIconButton`/`_SendButton`、`Keep the old paginated version for reference` 的 `_renderAndSavePagedOld`）；② 完整功能未挂入口（§9a 五项）；③ 预留 API 参数——构造参数在方法体内被读取（`size`/`onLongPress`/`haptics`/`hint` 等，删参数会破坏行为），仅是调用方暂不传值。
3. **连锁清理**（8 条）：删除后新暴露的 `_safeString`、`_TileStatus`、4 条 unused_import 一并删除；`pressedScale`（体内读取）加 ignore；`_userMenuActive` 入 §9a。
4. **方法学**：块边界用括号平衡时，`{` 仅在 `paren==0` 时计为函数体开始（否则命名参数表 `{...}` 同行闭合会被误判为块结束，B4 实测踩坑并回滚重做）。

---

## 6. 红线（违反即停下）

1. **pubspec.yaml 被动了就是事故**：`dart fix --apply` 会顺带应用 `missing_dependency`，实测往 `pubspec.yaml` 塞了 `path/characters/syncfusion_flutter_core/vector_math: any`。**每批 apply 后必须 `diff pubspec.yaml` 并还原**（T4：未经批准不得加依赖）。
2. **禁止批量盲删**：B/C 档逐条确认；初始化表达式有副作用（网络/IO/状态变更）的只去变量名，保留表达式。
3. **删除前 grep 确认**：`unused_element` 可能被 `dynamic` 调用或字符串反射命中；删除前必须在全仓 grep 标识符。
4. **不引入新 warning**：每批结束后，本次涉及文件不得出现基线里没有的新条目。
5. **info 不在本轮范围**：2836 条 info（585 条 `deprecated_member_use` 集中在 `lib/desktop/`）属长期项，等 Flutter SDK 升级窗口再处理，不设死线。
6. **commit 粒度**：一批一 commit，禁止"顺手重构"混进同一 commit（AGENTS.md §3）。
7. **禁止对 `unused_element_parameter` 用 `dart fix`**：Dart 3.9 把构造函数初始化形参 `this.x`（哪怕 `widget.x` 明明在用）判为未使用，`dart fix` 会直接删掉构造参数 → 残留 `final x;` 无初始化 → 15 个 `final_not_initialized_constructor` 编译错误。这 34 条只走人工。
8. **批量删除禁用全局文本匹配**：B3 踩坑——`final settings = context.read<SettingsProvider>();` 在同文件出现 6 处，按文本全局删会误删 5 处在用的。删除必须**行号 + 内容双断言**，删后立即 analyze。语句边界判定须剔除行尾注释（`const maxW = 280.0; // 注释` 以注释结尾，被误判跨语句，吞掉了后面的 `items` 块）。
9. **不许"顺手美化"自动修复的产物**：`unnecessary_cast` 修复会留下 `(body)[k]` 这类多余括号；批量去括号时 `Overlay.of(context).x` 会被误伤成 `Overlay.ofcontext`——`(...)` 可能是调用参数而非分组。已尝试并撤回，收益（好看）< 风险（编译错）。
9. **l10n 生成物会被 `flutter pub get` 覆盖**：`lib/l10n/app_localizations*.dart` 由 ARB 重新生成。0.0.43 曾把 `statsHeatmapSummary` 注入到类外（顶层无体声明），CI 因重新生成而侥幸通过，本地不跑 `pub get` 就报 4 个 error。**改 l10n 永远先改 ARB**（AGENTS.md T2）。

---

## 7. 进度看板

| 批次 | 状态 | 起始 | 结束 | 剩余 | commit |
|---|---|---:|---:|---:|---|
| B0 环境+基线 | ✅ 完成 | 438 | 438 | 438 | `c203caa` |
| B1 A 档自动修复（10 条规则） | ✅ 完成 | 438 | 248 | **248** | `78b9c1c` |
| B2 shown_name + field | ✅ 完成 | 248 | 220 | **220** | `0a3124d` |
| B3 local_variable | ✅ 完成 | 220 | 136 | **136** | `3703d87`（CI ✅ 136/0 核对）|
| B4 element + element_parameter | ✅ 完成 | 136 | 44 | **44** | `8d8fe19`（27 文件 +40/−1011）|
| B5 C 档语义 | ✅ 完成 | 44 | 0 | **0** 🎉 清零 | 见 git log（19 文件）|
| B6 门禁硬化 | ⬜ 待执行 | 0 | 0 | **0（保持）** | — |

**B5 处置明细**：14 条 `unreachable_switch_default` 按拍板保留 default + 行尾 ignore；20 条 `dead_null_aware_expression` 右侧均为字面量/getter 链（无副作用）全部删除；`dead_code`——`chat_api` 不可达 `return` 删除、`if (false && …)` 与 `tts cancelled` 保留 + ignore 入 §9a；`unnecessary_type_check`——`(b is Map)` 恒真删除、`schema is Map` 防御性检查（作者注释 depends on package）保留 + ignore；`invalid_use_of_protected_member`——`_pushConsole` 从 extension 移入 `_HtmlPreviewDialogState` 类体（extension 调 protected `setState` 违规）。

---

## 8. 清零之后

1. CI 步骤改为 `flutter analyze --no-fatal-infos`（去掉 `continue-on-error`），warning/error 阻塞合并。

---

## 9. 疑似功能未完成清单（B2/B4 发现，待用户确认）

### 9a. B4 新增：完整实现但未挂入口的 UI（已加 `// ignore: unused_element` 保留）

| 文件 | 元素 | 现象 |
|---|---|---|
| `lib/desktop/desktop_settings_page.dart` | `_showNetworkDialog` | 完整的代理设置对话框（proxyHost/Port/用户名密码），无调用入口 |
| `lib/desktop/desktop_settings_page.dart` | `_ToggleRowHaptics*` ×6 | 触觉反馈开关行（绑定 `hapticsGlobalEnabled` 等真实 provider 状态，`Haptics.setEnabled` 已生效），入口未挂载 |
| `lib/features/assistant/pages/assistant_settings_edit_page.dart` | `_McpTab`（165 行） | 助手 MCP 标签页，watch 两个 provider 过滤已连接服务器，未挂入 tab 栏 |
| `lib/features/assistant/pages/assistant_settings_edit_page.dart` | `_pickLocalAvatar` / `_inputEmojiDialog` | 本地相册选头像 + emoji 输入对话框，完整实现无入口 |
| `lib/features/chat/widgets/chat_message_widget.dart` | `_userMenuActive` | 用户菜单激活态，注释"for bubble highlight/scale"，只写不读（B4 删除 `_removeUserMenuOverlay` 连锁暴露）|
| `lib/core/providers/tts_provider.dart` | `cancelled` | **疑似真 bug**：网络 TTS 取消链路残缺——`var cancelled = false` 后从未置 true，`_cancelFlag` 闭包永远返回 false（synthesize 取消轮询永不触发），`if (cancelled) return` 恒 false。需在 stop/dispose 处接线 `cancelled = true` |
| `lib/core/services/api/chat_api_service.dart` | `if (false && …)` L2751 | Response API 的 tool_calls follow-up 流程被手动禁用（`false &&` 短路），整块代码保留。需决策：恢复启用或删除 |

### 9b. B2 发现：被赋值但从未读取的字段（已加 `// ignore: unused_field` 保留）

以下字段**被赋值但从未读取**——状态维护了、UI 没消费。已加 `// ignore: unused_field` 保留（删除会丢失功能意图）。需确认是"补完 UI"还是"删掉状态"：

| 文件 | 字段 | 现象 |
|---|---|---|
| `lib/desktop/setting/backup_pane.dart` | `_remote` / `_loadingRemote` | 拉取了远程备份列表却从不展示 |
| `lib/features/model/widgets/model_select_sheet.dart` | `_favItems`（×2 处） | 收藏列表加载但未渲染 |
| `lib/features/provider/pages/provider_detail_page.dart` | `_proxyEnabled` | 代理开关状态未绑定 UI |
| `lib/features/home/widgets/chat_input_bar.dart` | `_searchEnabled` | 搜索开关状态未被消费 |
| `lib/desktop/model_edit_dialog.dart` | `_searchTool` / `_urlContextTool` | 工具开关状态未绑定勾选框 |
| `lib/features/chat/widgets/chat_message_widget.dart` | `_inlineThinkWasLoading` | 思考中状态未被消费 |
| `lib/shared/pages/webview_page.dart` | `_consoleOpen` | 控制台开合状态未被消费 |
| `lib/desktop/desktop_nav_rail.dart` | `_hovered` | 悬停态未用于渲染 |
| `lib/desktop/setting/about_pane.dart` | `_pressed`（×2 处） | 按下态未用于渲染 |
| `lib/desktop/html_preview_dialog.dart` | `_tempFilePath` | Windows 临时文件路径未释放 |
| `lib/core/services/logging/logger.dart` | `_maxPayloadChars` | 日志截断上限定义了但未实现截断 |

**其中两个可能是真 bug，建议优先看**：
- `backup_pane` 的远程备份：列表拉下来了却不显示，用户会以为功能已完成。
- `html_preview_dialog` 的 `_tempFilePath`：临时文件写出去没清理，Windows 上可能积累残留文件。
2. 更新 `AGENTS.md` §5.4：基线数字由 438 改为 0，进入"增量红线"阶段。
3. `lib/desktop/` 的 585 条 `deprecated_member_use` 单独立项（`deprecated_member_use` 是 info，不阻塞门禁）。
