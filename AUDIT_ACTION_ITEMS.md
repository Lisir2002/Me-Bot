# Kelivo 整改追踪清单

> 来源：ARCHITECTURE_AUDIT.md（2026-09-05）
> 状态说明：⬜ 待处理 / 🔄 进行中 / ✅ 已完成 / ❌ 取消

---

## P0 — 阻塞级（必须修复）

### [P0-01] API Key / 代理密码迁移至安全存储

| 项 | 内容 |
|---|---|
| **问题** | API Key（含多 Key 轮转）、代理凭据明文存储在 SharedPreferences |
| **影响范围** | SettingsProvider、备份导出、恢复导入 |
| **建议方案** | 引入 `flutter_secure_storage`，创建 `SecureStorageService` 抽象层 |
| **平台差异** | Web 端无 secure storage，降级为 LocalStorage（接受一定风险） |
| **迁移策略** | 首次启动时从 SharedPreferences 读取 → 写入 secure storage → 清理旧键 |

**任务拆分：**

- [ ] 添加 `flutter_secure_storage: ^9.0.0` 到 pubspec.yaml
- [ ] 创建 `lib/core/services/secure_storage_service.dart`，封装读写接口
- [ ] 修改 `ProviderConfig` 加载/保存逻辑：API Key 字段走 secure storage
- [ ] 修改全局代理密码字段：走 secure storage
- [ ] 添加一次性迁移：`_migrateToSecureStorage()`，处理用户升级
- [ ] 修改备份导出：API Key 字段可选择脱敏或加密导出
- [ ] Web 端降级方案实现（LocalStorage + 运行时警告）

**验证：**
- [ ] Android：root 设备检查 /data/data 下 xml 文件无明文 API Key
- [ ] iOS：检查 NSUserDefaults 无明文 Key，Keychain 中有条目
- [ ] 已配置 API Key 的旧用户升级后 Key 不丢失

---

### [P0-02] 为关键路径补充单元测试

| 项 | 内容 |
|---|---|
| **问题** | 0 测试覆盖 |
| **建议方案** | 从最容易出 bug、最难人工验证的路径开始 |
| **优先级** | ChatService → ChatApiService → SettingsProvider → ApiKeyManager |

**任务拆分：**

**第一批（价值最高，不依赖 UI）：**
- [ ] `test/core/services/chat_service_test.dart`
  - [ ] 草稿会话 createDraftConversation + addMessage 自动落盘
  - [ ] deleteConversation 后孤儿文件清理逻辑（mock file system）
  - [ ] 会话 fork 完整流程
  - [ ] 消息版本管理（groupId + version + versionSelections）
  - [ ] truncateIndex 切换
  - [ ] _migrateSandboxPaths 路径迁移
  - [ ] 并发 addMessage 不丢失

- [ ] `test/core/models/chat_message_test.dart`
  - [ ] toJson / fromJson 往返
  - [ ] copyWith 每个字段的默认值处理
  - [ ] reasoningText / reasoningSegmentsJson 边界情况

- [ ] `test/core/models/conversation_test.dart`
  - [ ] toJson / fromJson 往返
  - [ ] versionSelections 空 Map 与 null 处理

- [ ] `test/core/models/api_keys_test.dart`
  - [ ] 多 Key 轮转策略（roundRobin / priority / leastUsed / random）
  - [ ] consecutiveFailures 达到阈值自动禁用
  - [ ] enableAutoRecovery 定时恢复逻辑
  - [ ] loadBalance 顺序稳定性

**第二批（需要 mock http）：**
- [ ] `test/core/services/api/chat_api_service_test.dart`
  - [ ] _parseTextAndImages 正确解析 Markdown 图片和 [image:xxx] 标记
  - [ ] _effectiveModelInfo per-model override 合并逻辑
  - [ ] 多模态 base64 编码顺序（图片在文本前 vs 后）
  - [ ] fallback key 触发条件（用户未配置 + 特定 model + 特定 provider）
  - [ ] _customHeaders / _customBody override 合并

- [ ] `test/core/providers/settings_provider_test.dart`
  - [ ] _localeToTag / _parseLocaleTag 所有分支覆盖
  - [ ] _mapDeviceLocaleToSupportedTag（TW/HK/MO → 繁体）
  - [ ] _parseOverrideValue 类型推断（int/double/bool/null/json）
  - [ ] ProviderConfig 完整序列化/反序列化

---

### [P0-03] 修复前 20 处高频静默 catch

| 项 | 内容 |
|---|---|
| **问题** | 535 处 `catch (_)` 吞异常 |
| **方案** | 批量替换为 `catch (e) { logging.warning('上下文描述', e); }` |
| **排除标准** | 真的是可忽略的 best-effort（如 Hive 清理失败）可保留空 catch |

**高频场景清单（前 20 处按出现次数排序）：**

| # | 文件 | 位置 | 场景 | 建议处理 |
|---|---|---|---|---|
| 1 | chat_service.dart | ~10 处 | Hive 读写失败 | logging.warning + 用户提示（重要操作） |
| 2 | settings_provider.dart | ~20 处 | SharedPreferences JSON 解析失败 | logging.warning + 保留默认值 + 记录损坏的 key |
| 3 | main.dart | ~6 处 | addPostFrameCallback 内部操作失败 | logging.warning |
| 4 | chat_api_service.dart | ~15 处 | API 响应 JSON 解析失败 | logging.severe + 向上抛出让 UI 显示错误 |
| 5 | mcp_provider.dart | ~10 处 | MCP 服务器连接/调用失败 | logging.warning + 更新 connected/error 状态 |
| 6 | backup_provider.dart | ~8 处 | WebDAV 同步失败 | logging.warning + 重试提示 |
| 7 | search_service.dart | ~12 处 | 搜索请求失败 | logging.info（搜索可降级） |
| 8 | chat_service.dart._migrateSandboxPaths | 1 处 | 迁移失败 | logging.warning + 下次启动重试 |

---

## P1 — 架构级（强烈建议）

### [P1-01] 超大文件拆分

| 文件 | 行数 | 拆分方案 |
|---|---|---|
| features/home/pages/home_page.dart | 6,202 | → HomePage + HomeAppBar + HomeBody + HomeTabBar + HomeStatusBar |
| features/assistant/pages/assistant_settings_edit_page.dart | 6,147 | → AssistantEditPage + SystemPromptEditor + ModelConfigPanel + MCPBindingPanel + PersonalityEditor |
| desktop/desktop_settings_page.dart | 5,783 | → DesktopSettingsPage + 复用 features/settings/pages/ 中的子页（条件导入） |
| core/services/api/chat_api_service.dart | 3,725 | → ChatApiService + SseStreamParser + MultimodalEncoder + ResponseValidator + FallbackStrategy |
| features/chat/widgets/chat_message_widget.dart | 2,856 | → ChatMessageWidget + ChatMessageContent + ChatMessageActions + ChatMessageRelevance |

---

### [P1-02] SettingsProvider 拆分

```
拆分前: SettingsProvider (1952 行, 92 key)
拆分后:
├── ThemeSettingsProvider        # 主题、动态色、调色板、纯净背景
├── NetworkSettingsProvider      # 代理设置（HTTP/SOCKS5）、HttpOverrides.global
├── DisplaySettingsProvider      # 字体、显示偏好、桌面布局、消息气泡样式
├── SearchSettingsProvider       # 搜索服务配置（12 家）
├── TtsSettingsProvider          # TTS 网络服务配置
├── ProviderConfigStore          # API Provider + API Key 多 Key 管理
└── BackupSettingsProvider       # WebDAV 配置
```

**关键挑战：** 拆分后需要保证现有调用者（`context.watch<SettingsProvider>()`）能逐步迁移。建议：
1. 先创建新 Provider，SettingsProvider 保持为 Facade（内部委托给新 Provider）
2. UI 层逐步改用新 Provider
3. 最后删除 SettingsProvider

---

### [P1-03] 请求层增强

- [ ] 添加请求超时（默认 30s，可配置）
- [ ] 添加指数退避重试（默认 2 次，仅对 5xx/网络错误重试）
- [ ] 添加 CancelToken 支持（dart:io HttpClient 的 `close()`）
- [ ] 可选：评估迁移至 `dio`（拦截器体系成熟）

```dart
// 目标接口示例
abstract class LlmHttpClient {
  Future<Stream<ChatChunk>> chatStream({
    required ChatRequest request,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 2,
    Duration? initialRetryDelay,
    void Function()? onCancel,
    CancelToken? cancelToken,
  });
}
```

---

### [P1-04] main.dart 启动治理

**当前问题：** 启动逻辑散落在 main() 和 MyApp.build() 中，串行 await 阻塞。

**目标架构：**

```
main()
  └── Bootstrap.run()         ← 统一入口
       ├── Phase 1 (同步快速)
       │   ├── WidgetsFlutterBinding.ensureInitialized()
       │   ├── SystemChrome.setEnabledSystemUIMode()
       │   └── DesktopWindow.setup()（仅桌面）
       ├── Phase 2 (异步可并行)
       │   ├── SandboxPathResolver.init()
       │   ├── SystemFonts.loadAllFonts()（仅桌面）
       │   └── Analytics.optIn()
       └── runApp(MyApp())
```

**MyApp.build() 清理：**
- 移除所有 `addPostFrameCallback`
- 移除字体应用逻辑（提取到独立的 ThemeFactory 方法）
- Assistant 默认值、更新检查等移至对应 Provider 内部

---

### [P1-05] 全局错误处理恢复

```dart
void setupErrorHandling() {
  // 同步错误
  FlutterError.onError = (FlutterErrorDetails details) {
    // logging.severe + 可选 Crashlytics/Sentry 上报
  };

  // 异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    logging.severe('Async error', error, StackTrace.fromString(stack.toString()));
    return true; // 已处理
  };
}
```

---

## P2 — 改进项

- [ ] **P2-01** debugPrint 残留清理（76 处 → 换用 logging）
- [ ] **P2-02** 注释掉的代码清理 → 删除，依赖 git 历史
- [ ] **P2-03** 魔法字符串提取为常量（Provider key、model ID 等）
- [ ] **P2-04** `.gitignore` 确认 `lib/secrets/fallback.dart` 不包含真实密钥
- [ ] **P2-05** MCP stdio 添加允许/禁止命令白名单
- [ ] **P2-06** WebView 添加 URL allowlist，禁止 `file://` 和 `javascript://`
- [ ] **P2-07** Hive 单 box 迁移评估 → 数据量 >10 万条时升级 Isar
- [ ] **P2-08** Syncfusion 商业库许可确认
- [ ] **P2-09** Provider/Service 命名统一化
- [ ] **P2-10** l10n arb 中中文条目冗余清理

---

## 整改路线图建议

```
Q1（紧急，2 周内）
├── [P0-01] API Key 安全存储迁移
├── [P0-03] 前 20 处静默 catch 修复
└── [P0-02] 第一批单元测试（ChatService + API Key 轮转）

Q2（核心，4 周内）
├── [P1-01] 前 3 个超大文件拆分
├── [P1-02] SettingsProvider 拆分（Facade 模式渐进式）
├── [P1-04] main.dart 启动治理
├── [P1-05] 全局错误处理恢复
└── [P0-02] 第二批单元测试（ChatApiService + SettingsProvider）

Q3（中期，持续推进）
├── [P1-03] 请求超时 + 重试 + CancelToken
├── [P1-01] 剩余超大文件拆分
├── [P2-05] MCP stdio 安全分级
├── [P2-06] WebView URL 白名单
└── [P2-03] 魔法字符串常量化

Q4（长期，架构治理）
├── [P1-02] SettingsProvider 拆分收尾
├── [P2-07] Hive → Isar 评估（数据量达标时）
└── [P2-09] 命名体系统一化
```

---

*— 整改追踪清单 —*
