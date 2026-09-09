# AGENTS.md — MiniMe-Core（Me-Bot）

> AI 协助开发规范。`README.md` 面向人类读者；本文件约束 AI 编码代理在本仓库的**全部行为**。
> 优先级：用户当次对话指令 > 本文件 > 其他一切文档。回复语言：简体中文。

## 0. 项目身份

- Flutter 应用，包名 `minime_core`，对外品牌 **MiniMe-Core**，仓库 `Lisir2002/Me-Bot`。
- 代码标识符用英文，注释 / 文档 / commit message 用中文。
- 任何代码、注释、文档、发布物中品牌名只用 **MiniMe-Core**，禁止出现 Kelivo 等旧名。

## 1. 环境现实（先读，防止南辕北辙）

| 现实 | 规则 |
|---|---|
| 本地 SDK 两套：`/opt/flutter335` = **Flutter 3.35.7 / Dart 3.9.2**（与 CI `FLUTTER_VERSION` 对齐，可用）；`/opt/flutter` = 旧版 2.17（**禁用**） | **analyze 走本地**：`export PATH=/opt/flutter335/bin:$PATH PUB_HOSTED_URL=https://pub.flutter-io.cn`，全量约 48s，实测与 CI 逐条一致；**build / 产物仍只走 CI** |
| 沙箱网络受限（直连 GitHub 时好时坏） | 一切 GitHub 网络操作先读《沙箱受限网络访问GitHub实战经验.md》（hosts/DoH、Git Data API、CI 日志两步法） |
| CI 无硬性 analyze 门禁（渐进接入中，见 §5.4） | push 前自检：括号/引号平衡、新 API 存在性 grep、脚本产物 NUL 扫描 |

## 2. 硬性铁律（每条带事故锚点；拿不准就停下来问用户）

- **T1 品牌**：对外名称一律 MiniMe-Core。〔锚点：0.0.40 前的 README 遗留 Kelivo 旧名，需专门提交修正〕
- **T2 l10n 五处同步**：`lib/l10n/` 下 4 个 ARB 是唯一事实源；`app_localizations.dart` / `app_localizations_en.dart` / `app_localizations_zh.dart` 是**提交在仓库的生成物**，CI 可能按 ARB 重新生成；`StatsL10n` 包装器同步收口。任何 key 变更 = 4 ARB + 3 生成 Dart + 包装器五处同步，且**逐类校验值按语言区分**、注入脚本必须幂等并自校验。〔锚点：0.0.43 轮 zh_Hant 类被写入 23 处简体值（应为「總覽/快取 Tokens/則訊息」等），全部返工〕
- **T3 API 验证**：不确定的 API **禁止凭记忆使用**——先 grep 本地依赖源码（pub cache 已有 fl_chart 等），或 WebFetch 官方文档确认签名与语义。〔锚点：`MaterialLocalizations.firstDayOfWeek` 不存在（正确是 `firstDayOfWeekIndex`，0=周日）；`narrowWeekdays` 实为固定周日起始而非本地周序——两者都是凭记忆写错、CI 才暴露〕
- **T4 依赖**：新增依赖必须先获用户确认；新增 import 后检查同名符号冲突（尤其 intl 等导出通用类型的包）。〔锚点：引入 intl 后其 `TextDirection` 类与 dart:ui 冲突，`TextDirection.ltr` 编译报错〕
- **T5 脚本写码自校验**：脚本批量修改源文件后必须校验产物仍是合法文本（`file` 命令 + NUL 字节扫描 + JSON 解析）。〔锚点：占位常量字符串被写入 3 个 NUL 字节，grep 显示 binary file matches〕
- **T6 git 安全**：所有网络命令必须检查返回码/输出，**失败绝不能被吞**（`2>/dev/null` 禁用）；`reset --hard` 仅限使用明确确认过的完整 sha（API 响应里的 head sha 是可靠来源），禁止闭眼 `reset --hard origin/main`——fetch 失败时 origin 引用是陈旧的；禁止 `git push --force` 到 main。〔锚点：fetch 因 TLS 失败被吞，reset 把工作区退回 0.0.40，靠 reflog 恢复〕
- **T7 密钥**：PAT 只活在会话内变量/命令里，禁止写进任何文件、commit、issue、release。〔锚点：用户在对话中明文提供 PAT，属于一次性授权〕

## 3. 改动纪律

- **最小改动边界**：只修改任务直接涉及的文件。顺手重构、重命名、"顺便优化"必须先说明并获得同意，否则不做。
- **注释只写"为什么"**：不生成解释"是什么"的废话注释；未经要求不新建文档文件。
- **既有代码非任务必需不动**：不重命名、不改格式、不换实现风格；发现可改进点先报告，由用户决定。
- 遵循既有模式：新 widget 走 `features/` 既有分层；文案一律走 l10n（StatsL10n 收口模式），禁止硬编码用户可见字符串。

## 4. 行动边界（三级）

| 级别 | 事项 |
|---|---|
| **自主执行** | 读代码/文档；修改代码与项目文档；**push main**（提交信息用 `type(scope): 中文描述`）；触发 CI 验证；修复自己引入的编译错误 |
| **需用户明示** | 打 tag、发版（release）、版本号变更、新增依赖、修改 CI workflow、修改 README、对外发布任何内容 |
| **禁止** | `push --force`、删除 tag/release、把密钥写入库、绕过沙箱网络规则、未经确认的破坏性命令 |

## 5. 发布 SOP

### 5.1 版本号
- `0.0.x` patch 递增：每次发版 +1（`version: 0.0.N+N` 双写）；里程碑级演进（如 agent 工作区接入）由用户拍板升 minor（0.1.0）。
- 发版必须由用户明示（说"验证推送打 tag，发行"或等效话术）。

### 5.2 版本日志三档（发布时三档齐全，缺一不可）
| 档 | 载体 | 写法 |
|---|---|---|
| 📣 **用户档** | GitHub Release body 主体 | 收益导向、无技术黑话；写"你能感受到什么"，不写实现；加粗关键词、表格对比 |
| 🔧 **开发者档** | `CHANGELOG.md` 对应版本节 | Keep a Changelog v2 分类（Added/Changed/Fixed…，只写有实际影响的）；破坏性变更必须含 Before/After + 迁移步骤 |
| 🤖 **模型档** | `CHANGELOG.md` 同版本 `### For Agents` 小节 | 精确到**符号级**：变更的 API/标识符、可验证的行为语义断言、涉及文件路径、给下个会话的坑位预警与迁移提示；禁止"各种优化"类不可验证表述；紧凑列表、标识符原样反引号 |

> 三档源于同一份变更，但受众不同：用户档写成公告，开发者档写成档案，模型档写成索引。参照 LangChain 的实践——For Agents 节精确到 `ls` 空输出从 `[]` 变 `"No files found"` 这个级别。

### 5.3 发布流程
1. bump `pubspec.yaml` version → commit
2. push main（TLS 失败重试 ≥3 次后降级走 Git Data API：blob→tree→commit→ref，见经验文档 §9.2）
3. 建 annotated tag：API 路线 `POST /git/tags`（**object 必须完整 40 位 sha**）+ `POST /git/refs`
4. 触发 `build-stable.yml` workflow_dispatch：`build_android=true`，其余平台 false，`publish_release=true`，`release_tag=v0.0.N`
5. 轮询 `actions/runs/{id}`；失败则按经验文档 §9.1 两步法拉日志（**第二步裸 GET，不带 Authorization**）
6. PATCH release body（用户档）；同步写 `CHANGELOG.md`（开发者档 + 模型档）
7. 资产校验：APK 文件名含正确版本号；与上一版 **sha256 必须不同**（防重复包；字节数可能因 zip 对齐恰好相同）

### 5.4 CI analyze 门禁（分级推进）
android job 已插入观察步骤：`flutter analyze | grep -v "info •"`（`continue-on-error: true`；过滤 info 是因为 Actions 单步输出会截断）。
**准确基线（2026-09-08，commit `c203caa`）：3074 issues = 438 warning + 2836 info + 0 error**。首轮报的"约 235 warning"是截断导致的错数，作废。
- warning 三条大头：`unused_local_variable` 84 · `unnecessary_cast` 73 · `unused_element` 60；最脏文件 `chat_api_service.dart` 89 条。
- info 最大单头 585 条 `deprecated_member_use`，集中在 `lib/desktop/`（desktop_settings_page 244 条）。

**清零行动见 `docs/WARNING_CLEARANCE.md`（批次 B0–B6、进度看板、红线）。** 已拍板政策：`unreachable_switch_default` 保留 default + ignore 注释；`unused_element` / `unused_field` 逐条判断。三条硬约束：
- `dart fix --apply` 会顺带应用 `missing_dependency` 往 `pubspec.yaml` 塞 `xxx: any`——**每批 apply 后必须 diff 并还原 pubspec**（T4）。
- **禁止对 `unused_element_parameter` 用 `dart fix`**：Dart 3.9 对初始化形参 `this.x` 是误报（`widget.x` 明明在用），机器修复会直接删构造参数，实测引入 15 个 `final_not_initialized_constructor` 编译错误。B1 已整条撤出，转人工。
- "未使用"类警告（原 201 条）无机器修复，**禁止批量盲删**，须逐条确认无副作用后再处理。B3/B4 已消化 179 条（unused_local_variable / unused_element / unused_element_parameter 已归零；剩 unused_field 1 条为保留字段）。

硬化路径：① 按批次清零 438 个 warning（**B1 `78b9c1c` 438→248 · B2 `0a3124d` 248→220 · B3 `3703d87` 220→136 · B4 136→44（unused_element/parameter 归零，27 文件 +40/−1011），全程 error 0，B1/B2/B3 均 CI 核对通过**）② CI 步骤改为 `flutter analyze --no-fatal-infos`（error/warning 阻塞，info 继续观察）③ info 长期逐步消化，不设死线。**B5 已落地：44 → 0（19 文件），warning 清零达成，全程 error 0**。§9a 保留项均带 ignore 注释。
基线已归零（2026-09-09，B5）：**增量红线生效——任何变更不得引入新 warning/error**。B6 已把 CI analyze 升级为**硬门禁**（`--no-fatal-infos` + 去 continue-on-error + `PIPESTATUS` 传退出码），warning/error 直接阻塞 job。

**§9a 修复专项（2026-09-09，`8a65787`）**：三个用户可感知 bug 已修复——① TTS 网络合成取消链路（每请求独立 `_TtsCancelToken`，stop/dispose 置位；主动取消不写 `_error`）；② backup_pane 远程列表预取死代码删除 + 弹窗 `_load()` 吞错误改为透出失败详情（实际展示走"恢复"按钮 → `_RemoteBackupsDialog`，功能本就完整）；③ html_preview_dialog Windows 临时文件泄漏（`_tempFiles` 跟踪全部写入路径，dispose 清理）。analyze 2589 issues 持平、0 warning。§9a 余下保留项（haptics 入口、`_McpTab`、头像、代理对话框、`if (false &&)` follow-up）待用户逐项拍板。

## 6. 索引表（本文件只做索引，不复制内容）

| 主题 | 去处 |
|---|---|
| 沙箱网络突破：hosts/DoH、CI 日志两步法、Git Data API 推送、fetch 事故守则 | 《沙箱受限网络访问GitHub实战经验.md》 |
| 版本历史与破坏性变更 | `CHANGELOG.md` |
| 架构与功能概览 | `README.md` |
| CI workflow | `.github/workflows/build-stable.yml`（FLUTTER_VERSION 3.35.7，B6 起 analyze 为硬门禁） |
| **warning 清零批次、进度看板、红线** | `docs/WARNING_CLEARANCE.md` |

## 7. 本文件的迭代

- 出现新事故 → 在 §2 新增**带锚点**的条款（没有锚点的规则不立）。
- 条款失效 → 删除，不恋战。措辞用肯定句（"总是先 X"，而非"别忘了 X"）。
- 每次发版时回顾一遍：本版踩的坑是否已沉淀。
