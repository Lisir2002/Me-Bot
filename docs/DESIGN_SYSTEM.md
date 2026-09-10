# Me-Bot 设计系统使用约定（强制）

> 2026-09-10 UI 对齐批次定稿。目标：**任何新页面都必须走设计系统 UI 层，不允许再手写风格**。
> 以下规则由 custom_lint 在 IDE 与 CI 双端强制执行（error 级，阻塞合并）。

## 一、为什么有这份约定

安全中心页（security_page）上线时直接手写了 Material 风格（裸 Scaffold + AppBar、
SwitchListTile、原生 SnackBar、Colors.red 硬编码），与 AppPage / AppSectionCard /
showAppSnackBar 的 iOS 风格体系严重割裂，移动端与桌面端还各炸出一层标题栏。
本约定与三条 lint 规则就是为了让这类问题**在写码时就报红，而不是上线后被用户发现**。

## 二、组件映射表（禁止 → 必须用）

| 禁止（lint error） | 必须使用 | 说明 |
|---|---|---|
| `Scaffold(` + `AppBar(` | **`AppPage`**（`shared/widgets/app_page.dart`） | 页面骨架唯一入口：标题、返回键、actions、滚动、SafeArea、分段、三态 |
| `SnackBar` / `ScaffoldMessenger` | **`showAppSnackBar`**（`shared/widgets/snackbar.dart`） | 语义类型 `NotificationType.success/error/info/warning`，支持 action 与点按 |
| `ListTile` / `SwitchListTile` / `ExpansionTile` 等 | **`AppNavRow`** / **`AppSwitchRow`**（`shared/widgets/app_section.dart`） | iOS 分组行：图标列 36px、按压缩放色位移、自带 ChevronRight、触觉 |
| 裸 `Container` 卡片 / `Card(` | **`AppSectionCard`** | iOS 分组卡，含边框/圆角/纯色背景联动 |
| 手写 `Divider(indent: ...)` | **`AppSectionDivider`** | 缩进默认对齐图标列（54） |
| `showModalBottomSheet`（简单选择弹层） | **`showAppSheet` + `AppSheet`**（`shared/widgets/app_sheet.dart`） | 圆角/grabber/标题/键盘避让统一；复杂交互弹层（拖拽分栏等）可自建 |
| `Colors.red / green / amber` 语义色 | **`AppStatusColor.success / danger / warning`**（`theme/design_tokens.dart`） | 语义状态色唯一事实来源（与 snackbar 同源） |
| 魔法数字间距/圆角 | **`AppGap` / `AppRadius` / `AppPagePadding`** | 间距 2/4/8/12/16/20/24/32/48，圆角 12/16 |
| Material Icons（`Icons.xxx`） | **`Lucide.*`**（`icons/lucide_adapter.dart`） | 全项目图标统一 Lucide；新图标需先在 adapter 子集中确认/补充 |
| `MaterialLocalizations` 返回键 | `AppPage` 自带 leading | 自动 `IosIconButton` + `arrow_back_ios_new_rounded` + Tooltip |

**允许保留的例外**（项目惯例，非 error）：
- `AlertDialog` 确认/输入对话框（10+ 文件惯例，桌面端比 sheet 更合适）；
- `InputChip` / `ActionChip`（无设计系统等价物）；
- `FilledButton` / `TextButton` / `OutlinedButton`（按钮体系暂不收口）。

## 三、AppPage 五段速查

```dart
class XxxPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage(
      title: l10n.xxxTitle,            // 纯文本标题（富标题用 titleWidget）
      body: const XxxBody(),           // 正文；需要多端复用时拆成无 Scaffold 的 Body
      // 常用槽位：actions / leading / showBack / scrollable / bodyPadding
      //           segments(分段) / states(一次性 Future 三态) / bottom / fab
    );
  }
}
```

- 响应式页面（Provider 驱动）**不要用 `states:`**，在 body 里手动判断 loading/error；
- body 需要桌面端复用时（如设置 pane 内嵌），Body 自带 ListView 并传 `scrollable: false`。

## 四、新页面 Checklist（提 PR 前自查）

- [ ] 页面壳是 `AppPage`，没有裸 `Scaffold`/`AppBar`（`no_raw_scaffold`）；
- [ ] 所有通知走 `showAppSnackBar`，并选对了 `NotificationType`（`no_material_snackbar`）；
- [ ] 所有列表行走 `AppNavRow` / `AppSwitchRow`，分组容器用 `AppSectionCard`（`no_material_list_tile`）；
- [ ] 分组小节标题用 13px w600 小节头（参考 `backup_page.dart` 的 `header` 范式）；
- [ ] 没有散落的 `Colors.green/red/amber`，语义色取 `AppStatusColor`；
- [ ] 图标全部 `Lucide.*`（新图标先去 `lucide_adapter.dart` 补子集）；
- [ ] 文案全部走 `context.l10n.xxx`（`hardcoded_ui_string` 会拦中文硬编码）；
- [ ] 桌面端嵌入的 body 无 Scaffold（避免双层标题栏），`MaterialPageRoute` push 的页才有完整壳。

## 五、lint 规则与豁免机制

插件：`tools/l10n_lints`（custom_lint_builder）。运行：`dart run custom_lint --no-fatal-infos --no-fatal-warnings`。

| 规则 | 级别 | 拦截内容 |
|---|---|---|
| `no_raw_scaffold` | ERROR | 页面自写裸 `Scaffold` |
| `no_material_snackbar` | ERROR | `SnackBar` / `SnackBarAction` |
| `no_material_list_tile` | ERROR | `ListTile` / `SwitchListTile` / `CheckboxListTile` / `RadioListTile` / `ExpansionTile` / `AboutListTile` |
| `hardcoded_ui_string` | WARNING | UI 参数位硬编码中文 |
| `l10n_no_field_cache` | WARNING | 缓存 AppLocalizations 到字段 |

**豁免方式**：
- 裸 Scaffold 全屏特例（首页、图片查看、扫码、HTML 预览、WebView）：在文件内 Scaffold
  处写注释 `// ⚠️ 裸 Scaffold 豁免（no_raw_scaffold 白名单）：…原因`，规则检测到该标记
  即整文件豁免。已有白名单：`home_page` / `image_viewer_page` / `qr_scan_page` /
  `html_preview_page` / `webview_page`。
- 设计系统实现文件（`app_page.dart` / `snackbar.dart`）与 `test/`、`tools/` 天然豁免。
- 其他规则不支持文件级豁免（SnackBar/ListTile 不存在全屏特例场景）；确有极端场景
  需先在本文件追加讨论记录，再走 `// ignore: no_material_list_tile` 单点豁免。

**CI 门禁**：`build-stable.yml` 静态分析步中 custom_lint 已转 fatal（仅 ERROR 阻塞，
存量 WARNING/INFO 继续报告），违规即退出非 0，禁止合并。

## 六、参考实现（黄金范式）

- **列表分组页**：`lib/features/backup/pages/backup_page.dart`（header + AppSectionCard 范式）；
- **双端拆壳页**：`lib/features/security/pages/security_page.dart`
  （`SecurityPage` 移动薄壳 + `SecurityBody` 桌面嵌入，业务与 UI 分层）；
- **Tab 分段页**：`lib/features/assistant/pages/assistant_settings_edit_page.dart`
  （AppPage 壳 + 页内 pill 分段条放 body 首行）。
