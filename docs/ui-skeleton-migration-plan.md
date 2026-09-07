# UI 骨架迁移计划 — AppPage / AppSheet / AppStates

> 目标：把项目里手写 `Scaffold + AppBar + body padding` 的页面逐步迁移到
> [AppPage 骨架引擎](../../lib/shared/widgets/app_page.dart)，统一骨架、三态、分段、弹层。
>
> 本计划让每次迁移都有"入口 → 改动 → 验证"的明确路径，可逐条打勾。

---

## 一、技术底座（已完成，无需再动）

| 组件 | 文件 | 用途 |
|---|---|---|
| AppPage | `lib/shared/widgets/app_page.dart` | 页面骨架引擎（顶栏/分段/三态/底栏/抽屉槽位） |
| AppSegment / AppSegmentMode | 同上 | 分段模型：top=顶栏TabBar / bottom=页内底部分段 |
| AppPageStates | 同上 | AsyncSnapshot 三态状态机配置 |
| AppLoading / AppError / AppEmpty | `lib/shared/widgets/app_states.dart` | 三态占位组件 |
| AppSheet / showAppSheet | `lib/shared/widgets/app_sheet.dart` | iOS mini-sheet 底部弹层模板 |
| 设计 Token | `lib/theme/design_tokens.dart` | AppGap / AppRadius / AppPagePadding / AppText |

### 已迁移样板（✅ 4 个，作为参考范例）

| 页面 | 用到的特性 | 摘要 |
|---|---|---|
| `settings/pages/settings_page.dart` | AppPage 基础（leading/title/body） | 首个迁移范例 |
| `storage/pages/storage_page.dart` | 三态 + 自定义 leading/actions | provider 驱动 loading/error/data |
| `mcp/pages/mcp_tool_detail_page.dart` | segments top + AppEmpty | 顶栏 Tab 双落点 |
| `chat/widgets/reasoning_budget_sheet.dart` | AppSheet | 弹层样板收敛 |

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
| `provider/pages/provider_network_page.dart` | 155 | AppPage + 表单 body |

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
| `provider/pages/provider_detail_page.dart` | 2412（含 bottom）| AppPage + **segments bottom** + 三态，优先级最高但风险最大 |

---

## 三、迁移步骤模板（每个页面照此执行）

每迁一个页面，按下面 checklist 走，完成即在下方"进度登记"打勾。

```
[ ] 1. 通读页面，识别用到的槽位（leading/actions/segments/states/bottom/sheet）
[ ] 2. 用 AppPage 替换手写 Scaffold + AppBar
[ ] 3. body 里的 loading/error/empty 分支 → AppLoading/AppError/AppEmpty
[ ] 4. TabBar + TabBarView → segments: [AppSegment(...)]（segmentsMode: top）
[ ] 5. 页内底部导航 → segments（segmentsMode: bottom）或 bottom 槽位
[ ] 6. showModalBottomSheet 简单弹层 → showAppSheet + AppSheet
[ ] 7. 魔法数字 padding → AppPagePadding / AppGap
[ ] 8. 移除页面私有 _TactileIconButton 复制 → IosIconButton（共享）
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

### ✅ 批次 1（简单页）
- [ ] `chat/pages/select_copy_page.dart`
- [ ] `terminal/pages/terminal_placeholder_page.dart`
- [ ] `chat/pages/message_edit_page.dart`
- [ ] `settings/pages/google_fonts_picker_page.dart`
- [ ] `settings/pages/more_page.dart`
- [ ] `provider/pages/provider_network_page.dart`

### ⬜ 批次 2（中等页）
- [ ] `assistant/pages/tags_manager_page.dart`
- [ ] `settings/pages/theme_settings_page.dart`
- [ ] `storage/pages/storage_log_page.dart`
- [ ] `storage/pages/storage_cache_page.dart`
- [ ] `storage/pages/storage_detail_page.dart`
- [ ] `chat/pages/chat_history_page.dart`
- [ ] `mcp/pages/mcp_server_detail_page.dart`
- [ ] `settings/pages/sponsor_page.dart`
- [ ] `translate/pages/translate_page.dart`
- [ ] `settings/pages/network_proxy_page.dart`
- [ ] `storage/pages/storage_media_page.dart`
- [ ] `mcp/pages/mcp_page.dart`
- [ ] `quick_phrase/pages/quick_phrases_page.dart`

### ⬜ 批次 3（复杂页）
- [ ] `model/pages/default_model_page.dart`
- [ ] `assistant/pages/assistant_settings_page.dart`
- [ ] `storage/pages/local_snapshot_page.dart`
- [ ] `settings/pages/about_page.dart`
- [ ] `settings/pages/tts_services_page.dart`
- [ ] `provider/pages/multi_key_manager_page.dart`
- [ ] `settings/pages/display_settings_page.dart`
- [ ] `provider/pages/providers_page.dart`

### ⬜ 批次 4（大复杂度页）
- [ ] `settings/pages/usage_stats_page.dart`
- [ ] `backup/pages/backup_page.dart`
- [ ] `search/pages/search_services_page.dart`
- [ ] `provider/pages/provider_detail_page.dart`

---

## 五、迁移顺序理由（建议按此推进）

1. **批次 1 优先**：6 个简单页，单页 ≤30 分钟改完，风险极低，快速积累一致性
2. **批次 2**：引入 TabBar（mcp_server_detail）和三态，验证 segments top + states
3. **批次 3**：多弹层页面（tts/display/multi_key），把 69 处 showModalBottomSheet 逐步收敛到 AppSheet
4. **批次 4 最后**：provider_detail 是唯一已用 bottomNavigationBar 的，用它验证 **segments bottom（页内底部分段）** 路径后再收尾

> ⚠️ 每批完成后**必须编译验证**（本机 flutter analyze + CI Android），再进下一批。
> 已迁移页的回归以手工真机为主，不引入额外测试框架。