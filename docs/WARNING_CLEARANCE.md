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
| | `unused_element_parameter` | 34 | 参数改名 `_`（回调签名要求不能删参数） | ✅ 34 |
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
| **C 语义** | `dead_null_aware_expression` | 19 | `a ?? b` 中 b 永不执行——**先确认 b 无副作用**再删 | ❌ |
| | `unreachable_switch_default` | 14 | 防御性 default：倾向保留 + ignore（见 §5 决策） | ❌ |
| | `dead_code` | 6 | 删恒假分支 | ❌ |
| | `invalid_use_of_protected_member` | 1 | 重构调用点 | ❌ |

**实测推演**：在副本上执行 A 档 11 条规则的 `dart fix --apply`，**438 → 214（消 224 条）**，且未引入任何 error。剩下 214 条全部落在 B/C 档。

---

## 4. 批次计划

| 批次 | 内容 | 条数 | 手法 | 预期剩余 |
|---|---|---:|---|---:|
| **B0** | 环境打通 + 基线锁定 + 推演 | — | 装 SDK / 对齐 CI / 副本实测 | 438 |
| **B1** | A 档全部（11 条规则） | 224 | `dart fix --apply --code=…` 逐规则执行 | 214 |
| **B2** | B 档 `unused_shown_name` + `unused_field` | 27 | 脚本 + 逐条确认 | 187 |
| **B3** | B 档 `unused_local_variable` | 84 | **逐条人眼判读**（副作用风险） | 103 |
| **B4** | B 档 `unused_element` | 60 | 逐条判读，区分"真废弃 / 预留 API" | 43 |
| **B5** | C 档全部 | 40 | 逐条判读 + 少量重构 | 0~14 |
| **B6** | 门禁硬化 | — | CI 改 `--no-fatal-infos` | 0 |

**执行顺序原则**：先横扫 A 档（收益最大、风险最低、可逆），再按"文件聚集"纵切 B/C 档——同一文件的问题一次改完，diff 集中易 review，避免同一文件被反复改动。

每个批次的固定动作：
1. 副本执行 → 2. 本地 `flutter analyze`（warning 数必须单调下降、error 必须 0）→ 3. 把改动搬回工作区 → 4. commit（一个批次一个 commit，message 注明批次与条数）→ 5. push → 6. CI 观察步骤复核 → 7. 更新 §7 看板。

---

## 5. 三个必须拍板的处置政策（待用户确认）

| # | 议题 | 选项 |
|---|---|---|
| P1 | `unreachable_switch_default`（14） | ① 保留 default + `// ignore:`（防御未来新增枚举值）② 直接删 default ③ 逐条定 |
| P2 | `unused_element` / `unused_field`（83） | ① 一律删 ② 属预留 API 的加 ignore 保留 ③ 逐条判断（默认） |
| P3 | B1 落地方式 | ① 先出 diff 摘要给你看再落 ② 直接落并 push ③ 先只做单文件试点 |

---

## 6. 红线（违反即停下）

1. **pubspec.yaml 被动了就是事故**：`dart fix --apply` 会顺带应用 `missing_dependency`，实测往 `pubspec.yaml` 塞了 `path/characters/syncfusion_flutter_core/vector_math: any`。**每批 apply 后必须 `diff pubspec.yaml` 并还原**（T4：未经批准不得加依赖）。
2. **禁止批量盲删**：B/C 档 214 条逐条确认；初始化表达式有副作用（网络/IO/状态变更）的只去变量名，保留表达式。
3. **删除前 grep 确认**：`unused_element` 可能被 `dynamic` 调用或字符串反射命中；删除前必须在全仓 grep 标识符。
4. **不引入新 warning**：每批结束后，本次涉及文件不得出现基线里没有的新条目。
5. **info 不在本轮范围**：2836 条 info（585 条 `deprecated_member_use` 集中在 `lib/desktop/`）属长期项，等 Flutter SDK 升级窗口再处理，不设死线。
6. **commit 粒度**：一批一 commit，禁止"顺手重构"混进同一 commit（AGENTS.md §3）。

---

## 7. 进度看板

| 批次 | 状态 | 起始 | 结束 | 剩余 | commit |
|---|---|---:|---:|---:|---|
| B0 环境+基线 | ✅ 完成 | 438 | 438 | 438 | — |
| B1 A 档自动修复 | ⬜ 待执行 | 438 | 214（副本实测） | — | — |
| B2 shown_name+field | ⬜ 待执行 | 214 | 187 | — | — |
| B3 local_variable | ⬜ 待执行 | 187 | 103 | — | — |
| B4 unused_element | ⬜ 待执行 | 103 | 43 | — | — |
| B5 C 档语义 | ⬜ 待执行 | 43 | 0~14 | — | — |
| B6 门禁硬化 | ⬜ 待执行 | — | 0 | — | — |

---

## 8. 清零之后

1. CI 步骤改为 `flutter analyze --no-fatal-infos`（去掉 `continue-on-error`），warning/error 阻塞合并。
2. 更新 `AGENTS.md` §5.4：基线数字由 438 改为 0，进入"增量红线"阶段。
3. `lib/desktop/` 的 585 条 `deprecated_member_use` 单独立项（`deprecated_member_use` 是 info，不阻塞门禁）。
