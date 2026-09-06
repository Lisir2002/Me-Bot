# 存储空间 & 数据备份 功能设计文档

> 目标：复刻截图中的"存储空间"整套页面与交互，并对现有"数据备份"页进行重构对齐。
> 遵循项目既有的 iOS 风格设置体系（`_iosSectionCard` / `_iosNavRow` / `IosSwitch` / `_TactileRow`，Lucide 图标，haptics）。

---

## 1. 范围与现状

### 1.1 现有实现（复用为主）
| 内容 | 位置 | 现状 |
|------|------|------|
| 存储空间入口 | `lib/features/settings/pages/settings_page.dart#L275` | "聊天存储"行，仅展示 `FutureBuilder` 大小的 detail，**onTap 未跳转** |
| 数据备份页 | `lib/features/backup/pages/backup_page.dart` | 已有 备份管理(2开关)/WebDAV(设置·测试·恢复·立即备份)/本地备份(导出·导入·Cherry)，iOS 风格 widget 齐全 |
| 备份数据源 | `lib/core/providers/backup_provider.dart` | `BackupProvider`：`test/backup/restoreFromItem/listRemote/deleteAndReload/exportToFile/restoreFromLocalFile` |
| 备份引擎 | `lib/core/services/backup/data_sync.dart` | `DataSync`：打包 json/zip、WebDAV 上传、恢复、temp 文件等 |
| 目录访问 | `lib/utils/app_directories.dart` | upload/images/avatars/cache/cache-avatars |
| 图表 | `pubspec.yaml#L93` | `fl_chart ^0.68.0` 已存在（主存储页饼图/环形图复用） |

### 1.2 缺口（需新增/补齐）
- 主"存储空间"页（多段进度条/环形图 + 8 分类列表）
- 各类**子页面**（媒体型 / 只读明细型 / 可清理明细型 / 空态）
- **本地副本管理**页（snapshots 快照列表 + 设置项 + 恢复/导出/删除/保留）
- **日志**页 + **日志查看**页 + **日志设置底部弹窗**
- 数据备份页缺失：**备份提醒**、**本地副本**区、**S3**区、以及**导出/导入进度卡片**
- 内联**进度卡片组件**（阶段 + 百分比 + 字节进度）

---

## 2. 导航结构

```
settings_page.dart
├─ 数据备份（已有入口）──────────── BackupPage【重构】
│   └─ 导出为文件 → 内联进度卡片（新增组件）
└─ 聊天存储（改造 onTap 跳转）──── StoragePage【新建】
    ├─ 图片 / 助手图片…  → StorageMediaPage【媒体型：网格多选删除】
    ├─ 文件 / …            （同媒体型，空则显空态）
    ├─ 聊天记录 / 其他     → StorageDetailPage【只读明细】
    ├─ 本地副本             → StorageDetailPage + 「管理副本」按钮
    │                          └── LocalSnapshotPage【新建：副本管理】
    ├─ 助手                 → StorageDetailPage（固定"头像"子项）
    ├─ 缓存                 → StorageCachePage【可清理明细】
    ├─ 日志                 → StorageLogPage【查看+清理】
    │                          └── LogViewerPage【新建：日志查看】
    │                                └── LogSettingsSheet【新建：底部弹窗】
    └─ 其他                 → StorageDetailPage【只读明细】
```

---

## 3. 数据模型

### 3.1 `StorageCategory`（8 分类定长配置）
```dart
enum StorageCategoryType { media, readOnlyDetail, cleanableDetail, snapshotDetail }

class StorageCategory {
  final String title;            // l10n key
  final IconData icon;           // Lucide
  final Color color;             // 分段条/图标主色
  final StorageCategoryType type;
  final List<String> dirs;       // 关联目录相对路径
  final String cautionKey;       // 风险提示文案 key（三种之一）
}
```

### 3.2 目录映射
| 分类 | 目录 | 类型 | 备注 |
|------|------|------|------|
| 图片 | `images/` | media | 缩略图网格 |
| 文件 | `upload/` | media | 缩略图网格；空显空态 |
| 聊天记录 | 数据库文件 | readOnly | 见 3.4 |
| 本地副本 | `snapshots/` | snapshotDetail | 带"管理副本" |
| 助手 | `avatars/` | readOnly | 固定"头像"子项 |
| 缓存 | `cache/` + `cache/avatars/` + 系统 cache | cleanable | 可安全清理 |
| 日志 | `logs/`（上下/网络/运行） | cleanable | 可安全清理 |
| 其他 | `app_flutter/` 收尾 | readOnly | 扣除已分类目录 |

> 目录根统一来自 `AppDirectories.getAppDataDirectory()`。系统 `cache/` 用 `getTemporaryDirectory()`。

### 3.3 扫描结果模型
```dart
class StorageUsage {
  int bytes;
  int fileCount;
  List<StorageEntry> entries;   // 明细，子页面用
}
class StorageEntry {
  String name;
  String path;       // 完整路径（明细展示用）
  int bytes;
  DateTime modified;
  String source;     // user | assistant（媒体型来源筛选用）
}
```

### 3.4 聊天记录（sqlite 三件套）
- 目标：`<appData>/kelivo.db`、`kelivo.db-wal`、`kelivo.db-shm`
- 通过 `ChatService` 暴露的数据库文件路径获得（对齐 `getUploadStats` 的取数方式）
- 只读显示：名称 / `大小 · 1 个文件` / 完整路径；**不可直接删**（编辑 db 文件需经服务层）

---

## 4. 主存储页 `StoragePage`

### 4.1 顶部栏
- 返回 / 标题"存储空间" / 右侧**刷新**按钮（`_TactileIconButton` + `Lucide.RotateCw`）
- 刷新：重新触发全量扫描，有加载态

### 4.2 已用空间卡片（环形图）
- 标签："已用空间"
- 大号数值（合计 bytes，`AlbumView` 风格大字）
- 环形进度：用 `fl_chart` `PieChart`（`centerSpaceRadius` 出环形）或 CustomPainter 分段弧
- 分段数 = 8 分类，颜色映射 `StorageCategory.color`
- 图例 + "可清理空间"（= 缓存 + 日志 之和）提示

### 4.3 分类列表
- 复用 `_iosSectionCard`，每行 `_iosNavRow(icon, title, detail: "大小 · N 个文件")`
- `onTap` 跳转对应子页面
- 数据来自一次 `storageService.scanAll()`，状态由 `StorageProvider` 承载（ChangeNotifier）

---

## 5. 子页面（按类型）

### 5.1 媒体型 `StorageMediaPage`（图片/文件）
- 顶栏：返回 / 分类名 / 刷新
- 头部信息卡：分类名 + `大小 · N 个文件` + 风险提示
- **来源筛选** Segmented：全部 / 用户上传 / 助手发出（过滤 `StorageEntry.source`）
- **排序** Segmented：最新 / 最旧 / 最大 / 最小
- 操作条：`全选`（描边）+ `删除`（粉色填充）
- 计数"共 N 项"
- 网格：`GridView` 缩略图 + 右上角圆形选择框（多选用 `Set<String>` 存 path）
- 删除：确认对话框 → 调用服务层删除 → 重扫

### 5.2 只读明细型 `StorageDetailPage`（聊天记录/助手/其他）
- 顶栏 + 分类名 + `大小 · N 个文件` + 风险提示
- "明细"标题 + 卡片列表（名称 / `大小 · 一 文件` / 完整路径灰字）
- 无筛选/排序/删除
- 助手：固定"头像"子项，即使空也展示
- 本地副本：额外 `管理副本 ›` 行 + 说明卡（`snapshots/` 路径）

### 5.3 可清理明细型（缓存 / 日志）
- `StorageCachePage`：顶部两个描边按钮（清理头像缓存 / 清理缓存），每个卡片右侧独立"清理"
- `StorageLogPage`：顶部 `查看日志` / `清理日志`，卡片无独立按钮
- 提示文案为"可安全清理，不影响聊天记录。"

### 5.4 空态
- `entries.isEmpty` 时：隐藏筛选/排序/操作条，居中"暂无内容"

---

## 6. 本地副本管理 `LocalSnapshotPage`

### 6.1 设置卡
| 项 | 控件 |
|----|------|
| 保留本地副本 | 开关 |
| 备份频率 | 导航行 `自动 ›` |
| 保留份数 | 导航行 `3 份 ›` |
| 保留一份上周的 | 开关 |
| 保留一份上个月的 | 开关 |
| 占用上限 | 导航行 `10.0 GB ›` |
| 备份完成时提示 | 开关 |

- 底部说明 + `✓ 上次备份：...`
- `立即备份一份`（描边按钮）
- 设置持久化：`SettingsProvider`/`SharedPreferencesAsync`（对齐 data_sync 尾部已有封装）

### 6.2 备份列表
- 标题"本地副本 · N 份 · 总量"
- 每卡：数据库图标 + 时间 + 大小、"自动备份"、"3 个对话 · 14 条消息"
- 操作：`恢复` / `导出` / `删除`(粉) / `📌 保留这份`
- 目录：`snapshots/`
- 底部安全说明文案

---

## 7. 数据备份页 `BackupPage`【重构对齐】

目标结构（对照截图第七张）：
1. **备份管理**：聊天记录 / 文件 —— 已有，保留
2. **备份提醒**：定期提醒我备份 —— **新增开关**
3. **本地副本**：保留本地副本开关 + `管理副本 → 2 份 · 56.9 KB ›`（→ `LocalSnapshotPage`）+ 说明 —— **新增**
4. **本地备份**：导出为文件 / 备份文件导入 / 从 Cherry Studio 导入 / **从 Chatbox 导入** —— 已有 3 项，补 **Chatbox**
5. **WebDAV 备份**：服务器设置 / 测试连接 / 恢复 / 立即备份 —— 已有，保留
6. **S3 备份**：服务器设置 / 测试连接 / 恢复 / 立即备份 —— **新增**（`S3Provider`/客户端，若缺依赖需评估 `minio`/自定义 AWS SigV4）

---

## 8. 导出/导入进度卡片（新增组件）

对齐第十四张"导出为文件"内联效果：

### 8.1 `BackupProgressCard`
```dart
class BackupProgressCard extends StatelessWidget {
  final String title;         // "导出为文件"
  final double progress;      // 0.0~1.0
  final String phase;         // "正在打包 / 正在导出 / 正在校验"
  final int processedBytes;   // 已处理字节
  final int totalBytes;       // 总字节
}
```
- 圆角白底卡：`✓` 图标 + 标题、`LinearProgressIndicator`（蓝）、阶段 + 百分比、`processed/total` 字节

### 8.2 接入方式
- 替代现有 `_runWithExportingOverlay`（全屏 spinner）为**内联卡片**，放在触发行之下
- `DataSync` 提供 `Stream<BackupProgress>` 回调，`exportToFile` 改流式上报阶段与字节
- 导入（`restoreFromLocalFile` / WebDAV 恢复）也用同组件复用

---

## 9. 日志体系（新增子模块）

| 页面 | 说明 |
|------|------|
| `StorageLogPage` | 顶部查看/清理 + 明细卡（上下文/网络/运行三类，`logs/`） |
| `LogViewerPage` | 顶栏含设置齿轮；Tab：上下文 / 请求日志 / 应用日志；列表"当前日志 - 时间 ›" |
| `LogSettingsSheet` | 底部弹窗，drag handle + 标题"日志设置" |

### 9.1 日志设置项（SharedPreferences 持久化）
| 项 | 控件 | 说明 |
|----|------|------|
| 保存响应输出 | 开关 | 记录流式分片；HTTP 报错仍写 |
| 省略大载荷 | 开关 | base64 图片/文件 → 占位符 |
| 自动删除 | 导航行 `不启用 ›` | 按天数；选择器弹窗 |
| 日志大小上限 | 导航行 `50 MB ›` | 超出删最旧；选择器弹窗 |

---

## 10. 逻辑与交互要点

1. **全量扫描**：`StorageProvider.scanAll()` 在 isolate(`compute`) 中递归 `listSync(recursive:true)` 累加 bytes/count，避免 UI 卡顿；结果缓存，点分类即时渲染。
2. **可清理空间** = 缓存 + 日志 之和，随扫描更新。
3. **删除安全**：媒体型/缓存/日志删除前均二次确认；聊天记录/本地副本/其他禁止 UI 直接删。
4. **来源筛选**：需文件归属元数据（user/assistant）。现有上传未标记 → 建议在文件落盘时附带来源标记，缺失时一律按"用户"处理并在文档标注为**降级策略**。
5. **Haptics / 手感**：沿用 `_TactileRow`/`_TactileIconButton` + `Haptics.soft/light`，与全站一致。
6. **i18n**：所有文案进 `app_*.arb`（zh/en/zh_Hant/zh_Hans），页面用 `AppLocalizations`。

---

## 11. 文件清单（建议新增/改动）

| 文件 | 用途 |
|------|------|
| `lib/core/services/storage/storage_service.dart` | 目录扫描 / 分类统计 / 删除 / 快照管理 |
| `lib/core/providers/storage_provider.dart` | 状态（usage / 扫描 loading / 刷新） |
| `lib/core/models/storage.dart` | `StorageCategory`/`StorageUsage`/`StorageEntry`/枚举 |
| `lib/features/storage/pages/storage_page.dart` | 主存储页 |
| `lib/features/storage/pages/storage_media_page.dart` | 媒体型详情 |
| `lib/features/storage/pages/storage_detail_page.dart` | 只读明细详情 |
| `lib/features/storage/pages/storage_cache_page.dart` | 缓存页 |
| `lib/features/storage/pages/storage_log_page.dart` | 日志页 |
| `lib/features/storage/pages/log_viewer_page.dart` | 日志查看 |
| `lib/features/storage/widgets/log_settings_sheet.dart` | 日志设置弹窗 |
| `lib/features/storage/pages/local_snapshot_page.dart` | 本地副本管理 |
| `lib/features/backup/widgets/backup_progress_card.dart` | 导出/导入进度卡 |
| `lib/features/settings/pages/settings_page.dart` | 聊天存储行 onTap 跳转 |
| `lib/core/services/backup/data_sync.dart` | 进度流式上报 / Chatbox 导入 / S3 |
| `lib/features/backup/pages/backup_page.dart` | 重构补齐（提醒/本地副本/S3） |
| `lib/l10n/app_*.arb` | 新增文案 |

---

## 12. 依赖评估
- `fl_chart` 已有 → 主存储页环形图直接用
- S3 / WebDAV 基础库需按需评估；现有 WebDAV 已用自实现（dio 未出现在依赖中），S3 同理考虑最小自实现 SigV4 或新增轻量依赖
- 缩略图：图片预览可复用项目现有图片查看能力；本机图片用 `Image.file`

---

## 13. 验收 / 里程碑
1. **M1 主存储页**：环形图 + 8 分类 + 真实字节统计 + 刷新
2. **M2 子页面**：媒体型(筛选/排序/多选/删除) + 只读明细 + 空态 + 缓存/日志清理
3. **M3 本地副本管理**：设置卡 + 列表 + 恢复/导出/删除/保留 + 立即备份
4. **M4 数据备份重构**：提醒 / 本地副本区 / Chatbox / S3 + 进度卡片接入导出导入
5. **M5 日志体系**：存储 → 查看 → 设置弹窗

> 每里程碑以 `flutter analyze` 0 error + 页面可交互验收为完成标准。