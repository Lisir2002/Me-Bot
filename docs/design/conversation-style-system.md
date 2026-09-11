# 对话流样式系统设计文档

> 版本：v1.0
> 日期：2026-09-11
> 状态：设计阶段
> 适用范围：Me-Bot 全平台（Android / iOS / Desktop / Web）

---

## 1. 设计理念

### 1.1 核心思想

对话流样式不是固定的 UI 模板，而是**可插拔的渲染策略**。同一套对话数据，可以根据用户偏好和对话意图，动态选择最优的视觉呈现方式。

### 1.2 设计原则

| 原则 | 说明 |
|---|---|
| **数据与视图分离** | 15 种样式共享同一套 `MessagePart` 数据模型，切换样式不丢失内容 |
| **统一数据进出口** | 所有样式只能通过 `ConversationDataSource` 统一接口读写数据，禁止样式直接操作底层存储；切换样式时流式输出、工具调用状态、滚动位置等中间状态完整保留 |
| **用户自主 + 智能推荐** | 用户可手动选择，也可开启"自动模式"由系统根据意图推荐 |
| **渐进式披露** | 复杂样式默认折叠细节，按需展开，平衡信息密度和可读性 |
| **平滑过渡** | 样式切换有过渡动画，不闪屏、不跳变 |
| **按需加载** | 样式组件 lazy load，不增加首屏体积 |
| **可扩展** | 新增样式只需实现 `StyleRenderer` 接口，无需改动核心逻辑 |

### 1.3 用户价值

- **新用户**：自动模式开箱即用，无需理解样式差异
- **进阶用户**：可根据场景手动切换，提升效率
- **专业用户**：可针对不同助手/会话预设默认样式

---

## 2. 系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      设置层 (Settings)                       │
│  ┌──────────────┐  ┌──────────────────────────────────────┐ │
│  │ 全局样式偏好  │  │  per-assistant / per-conversation 覆盖│ │
│  └──────────────┘  └──────────────────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│               StyleResolver（样式解析器）                     │
│  输入：用户偏好 + 对话上下文 → 输出：ConversationStyle         │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│              StyleRenderer Registry（渲染注册表）             │
│  ┌────────┐ ┌────────┐ ┌────────┐        ┌────────┐        │
│  │Style 01│ │Style 02│ │Style 03│  ...   │Style 15│        │
│  └────────┘ └────────┘ └────────┘        └────────┘        │
│            所有渲染器只通过下方统一接口读写数据                 │
└──────────────────────────────┬──────────────────────────────┘
                               │ 唯一数据入口
┌──────────────────────────────▼──────────────────────────────┐
│         ★ 统一数据进出口层（ConversationDataSource）★         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  messageStream (BehaviorSubject) — 所有样式共享同一流   │  │
│  │  stateStream — 会话状态（生成中/错误/审批/连接）         │  │
│  │  sendMessage / retry / stop / approve / reject         │  │
│  │  流式输出、工具调用、思考过程全部写入此层，不经过样式      │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│              数据持久层（Hive / Provider / API）              │
│  样式层不可见，只能通过 DataSource 间接访问                   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 核心模块职责

| 模块 | 职责 |
|---|---|
| `ConversationStyle` | 枚举，定义 15 种样式标识符 |
| `StyleSettings` | 持久化用户偏好（全局/按助手/按会话） |
| `StyleResolver` | 根据上下文解析出最优样式 |
| `StyleRenderer` | 抽象接口，每种样式的具体实现 |
| `StyleRendererRegistry` | 注册/查找渲染器，支持 lazy load |
| `StyleSwitcher` | 样式切换控制器，处理过渡动画 |

---

## 3. 数据模型

### 3.1 统一消息模型

所有样式共享同一套 `MessagePart` 数据结构：

```dart
/// 消息角色
enum MessageRole { user, assistant, system, tool }

/// 消息部分类型（一条消息可包含多个 part）
sealed class MessagePart {
  String get id;
}

/// 文本部分
class TextPart extends MessagePart {
  final String text;
  final List<TextEntity>? entities; // 加粗、链接、代码等
}

/// 代码部分
class CodePart extends MessagePart {
  final String code;
  final String language;
  final String? filename;
}

/// 工具调用部分
class ToolCallPart extends MessagePart {
  final String toolName;
  final Map<String, dynamic> arguments;
  final ToolCallStatus status; // pending / running / success / error
  final dynamic result;
  final Duration? duration;
  final String? thinking; // 思考过程
}

/// 图片部分
class ImagePart extends MessagePart {
  final String url;
  final String? caption;
  final int? width;
  final int? height;
}

/// 文件部分
class FilePart extends MessagePart {
  final String name;
  final String url;
  final int size;
  final String mimeType;
}

/// 思考部分
class ThinkingPart extends MessagePart {
  final String content;
  final int? tokenCount;
  final Duration? duration;
}

/// 审批请求部分
class ApprovalPart extends MessagePart {
  final String action;
  final String description;
  final ApprovalStatus status; // pending / approved / rejected
  final Map<String, dynamic> details;
}

/// 产物部分（Canvas/Artifact）
class ArtifactPart extends MessagePart {
  final String artifactId;
  final ArtifactType type; // document / code / image / chart
  final String title;
}
```

### 3.2 样式枚举

```dart
enum ConversationStyle {
  classicBubble,         // 01 经典气泡式
  fullWidthDocument,     // 02 全宽文档式
  minimalStream,         // 03 极简流式
  cardStack,             // 04 卡片堆叠式
  agentThreeTier,        // 05 Agent 三层级（推荐）
  toolCardFlow,          // 06 工具卡片流
  thinkActObserve,       // 07 思考-行动-观察闭环
  terminal,              // 08 终端风格
  multiAssistant,        // 09 多助手协作
  richContent,           // 10 富内容渲染
  generativeUi,          // 11 生成式 UI
  threadBranching,       // 12 对话分支
  contextPanel,          // 13 上下文面板
  planSurface,           // 14 执行计划面板
  canvasArtifact,        // 15 画布产物
  auto,                  // 自动模式（特殊值，由 Resolver 决定）
}
```

### 3.3 样式设置模型

```dart
class StyleSettings {
  /// 全局默认样式
  final ConversationStyle globalStyle;

  /// 是否启用自动模式
  final bool autoModeEnabled;

  /// 按助手覆盖（assistantId -> style）
  final Map<String, ConversationStyle> assistantOverrides;

  /// 按会话覆盖（conversationId -> style）
  final Map<String, ConversationStyle> conversationOverrides;

  /// 自动模式的意图权重调整
  final Map<ConversationIntent, double> intentWeights;
}
```

### 3.4 统一数据进出口（核心架构）

> **这是整个样式系统的基石。所有样式渲染器只能通过以下统一接口读写数据，禁止直接访问 Hive/Provider/数据库。切换样式时，数据源、事件流、中间状态完全不变，只换渲染层。**

#### 3.4.1 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                    样式渲染层 (15 种 Style)                   │
│  只允许通过 ConversationDataSource 接口读取，通过事件回调交互   │
└──────────────────────────────┬──────────────────────────────┘
                               │ 唯一入口
┌──────────────────────────────▼──────────────────────────────┐
│              ConversationDataSource（统一数据接口）            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Stream<List<Message>> messageStream                   │  │
│  │  Stream<ConversationState> stateStream                 │  │
│  │  Future<Message?> getMessage(String id)                │  │
│  │  Future<List<Message>> getMessages({range})            │  │
│  │  Future<void> sendMessage(...)                         │  │
│  │  Future<void> retryMessage(String messageId)           │  │
│  │  Future<void> stopGeneration()                         │  │
│  │  Future<void> approveAction(String approvalId)         │  │
│  │  Future<void> rejectAction(String approvalId)          │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│              ConversationEventBus（统一事件总线）              │
│  流式输出事件 / 工具调用事件 / 状态变更事件 / 错误事件          │
│  所有样式订阅同一事件流，切换样式不丢失任何事件                 │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│              数据持久层（Hive / Provider / API）              │
│  样式层不可见，只能通过 DataSource 间接访问                   │
└─────────────────────────────────────────────────────────────┘
```

#### 3.4.2 ConversationDataSource 接口定义

```dart
/// 对话数据源 —— 样式渲染器的唯一数据入口
///
/// 所有样式必须通过此接口获取数据和发送操作，
/// 禁止直接访问 Hive、Provider、数据库或 API。
/// 切换样式时，此实例保持不变，中间状态完整保留。
abstract class ConversationDataSource {
  /// 当前会话 ID
  String get conversationId;

  /// 消息流 —— 所有样式订阅同一个流
  ///
  /// 重要：这是一个广播流（BehaviorSubject），
  /// 新样式订阅时立即收到当前完整消息列表，
  /// 不会丢失任何已生成的内容（包括流式输出中的部分内容）。
  Stream<List<Message>> get messageStream;

  /// 会话状态流
  Stream<ConversationState> get stateStream;

  /// 当前状态（同步获取，避免异步 gap）
  ConversationState get currentState;

  /// 当前消息列表（同步获取，用于首次渲染）
  List<Message> get currentMessages;

  /// 按 ID 获取单条消息
  Future<Message?> getMessage(String messageId);

  /// 分页获取历史消息
  Future<List<Message>> getMessages({
    DateTime? before,
    int limit = 50,
  });

  /// 发送用户消息
  ///
  /// 返回后，消息会立即出现在 messageStream 中（pending 状态），
  /// 随后流式更新。所有样式都能看到完整的状态变更过程。
  Future<void> sendMessage({
    required String content,
    List<Attachment>? attachments,
    String? referencedMessageId,
  });

  /// 重试某条消息（重新生成）
  Future<void> retryMessage(String messageId);

  /// 停止当前生成
  Future<void> stopGeneration();

  /// 审批通过（高风险操作）
  Future<void> approveAction(String approvalId);

  /// 审批拒绝
  Future<void> rejectAction(String approvalId, {String? reason});

  /// 切换样式（由 StyleSwitcher 调用，数据源本身不关心样式）
  /// 此方法只通知数据源"样式即将切换"，用于暂停/恢复流式渲染优化，
  /// 不改变任何数据状态。
  Future<void> onStyleWillChange(ConversationStyle newStyle);

  /// 样式切换完成
  Future<void> onStyleDidChange(ConversationStyle style);

  /// 释放资源（会话关闭时调用）
  void dispose();
}
```

#### 3.4.3 ConversationState（会话状态）

```dart
/// 会话运行时状态 —— 切换样式时完整保留
class ConversationState {
  /// 是否正在生成回复
  final bool isGenerating;

  /// 当前正在生成的消息 ID（流式输出中的消息）
  final String? generatingMessageId;

  /// 当前生成进度（0.0 - 1.0，工具调用场景）
  final double? generationProgress;

  /// 当前阶段描述（"正在搜索..." / "正在分析..." / "正在生成..."）
  final String? currentPhase;

  /// 待审批的操作列表
  final List<ApprovalRequest> pendingApprovals;

  /// 错误信息（如有）
  final ConversationError? error;

  /// 网络连接状态
  final ConnectionStatus connectionStatus;

  /// 最后一条消息的时间戳
  final DateTime? lastMessageAt;

  /// 未读消息数
  final int unreadCount;
}
```

#### 3.4.4 流式输出的中间状态保留

**问题**：用户在助手正在流式输出时切换样式，已输出的 token 不能丢失，输出不能中断。

**解决方案**：

```
流式输出流程（样式无关）：

API Stream → ConversationEventBus → MessagePart 增量更新
                                        │
                                        ▼
                              ConversationDataSource.messageStream
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
              Style A 渲染         Style B 渲染         Style C 渲染
            （切换前订阅）      （切换后立即收到      （按需订阅）
                                  当前完整内容）
```

关键设计：
1. **流式数据写入 DataSource，不经过样式层**：API 返回的 token 直接更新 `Message.parts`，然后通过 `messageStream` 广播
2. **新样式订阅时立即收到当前快照**：`BehaviorSubject` 语义，`messageStream` 的新订阅者立即收到 `currentMessages`（包含流式输出中的部分内容）
3. **样式切换不中断流**：`stopGeneration()` 只能由用户主动调用，样式切换不会触发
4. **滚动位置保留**：`ScrollController` 由 `ConversationView` 容器持有，不随样式销毁；新样式 attach 到同一个 controller

#### 3.4.5 工具调用状态保留

**问题**：工具调用正在执行中（pending/running）时切换样式，状态不能丢失。

**解决方案**：
- `ToolCallPart.status` 是数据模型的一部分，存储在 `Message.parts` 中
- 工具调用的状态变更（pending → running → success/error）通过 `messageStream` 广播
- 新样式渲染时直接读取 `ToolCallPart.status`，显示对应状态
- 工具执行的耗时计时器在 DataSource 层维护，不依赖样式层

#### 3.4.6 样式渲染器约束

```dart
/// 样式渲染器基类 —— 强制通过 DataSource 获取数据
abstract class StyleRenderer {
  /// 渲染器不持有任何数据，只持有 DataSource 引用
  @protected
  late final ConversationDataSource dataSource;

  /// 初始化时注入 DataSource（由 StyleSwitcher 统一注入）
  void attach(ConversationDataSource source) {
    dataSource = source;
    onAttach();
  }

  /// 样式被激活时调用（可订阅流）
  void onAttach();

  /// 样式被停用时调用（必须取消所有订阅）
  void onDetach();

  /// 构建 UI —— 只能从 dataSource 读取数据
  Widget build(BuildContext context);

  /// 禁止子类直接访问以下内容（通过 lint 规则强制执行）：
  /// - Hive box
  /// - Provider / Riverpod 的直接 read/watch
  /// - 数据库查询
  /// - 网络 API 调用
  /// 所有数据必须通过 dataSource 获取
}
```

#### 3.4.7 切换时的状态保留清单

| 状态项 | 保留方式 | 说明 |
|---|---|---|
| 已生成的消息内容 | `currentMessages` 快照 | BehaviorSubject 立即推送 |
| 流式输出中的部分内容 | `Message.parts` 增量 | 新样式收到完整 part 列表 |
| 工具调用状态 | `ToolCallPart.status` | 数据模型的一部分 |
| 工具调用执行中 | DataSource 层计时器 | 不依赖样式层 |
| 思考过程内容 | `ThinkingPart.content` | 数据模型的一部分 |
| 审批请求状态 | `ApprovalPart.status` | 数据模型的一部分 |
| 滚动位置 | 容器级 ScrollController | 不随样式销毁 |
| 输入框草稿 | 容器级 TextEditingController | 不随样式销毁 |
| 会话状态 | `ConversationState` | 独立于样式 |
| 错误状态 | `ConversationError` | 独立于样式 |
| 网络连接状态 | `ConnectionStatus` | 独立于样式 |

#### 3.4.8 自定义 Lint 规则（强制执行）

为了防止样式渲染器绕过统一接口，新增两条 custom_lint 规则：

```yaml
# analysis_options.yaml
custom_lint:
  rules:
    - style_renderer_no_direct_data_access:
      # StyleRenderer 子类中禁止直接 import Hive/Provider/数据库/API
      forbidden_imports:
        - 'package:hive/**'
        - 'package:provider/**'
        - 'package:flutter_riverpod/**'
        - '**/database/**'
        - '**/api/**'
      # 只能 import ConversationDataSource
      allowed_data_imports:
        - '**/conversation_data_source.dart'

    - style_renderer_must_attach_datasource:
      # StyleRenderer 子类必须在 build 中使用 dataSource
      # 不能在 build 方法外持有可变数据状态
```

### 3.5 UI 状态跨样式同步（ConversationUIState）

> 数据状态由 DataSource 管理，UI 状态（展开/折叠、选中标签等）由独立的 `ConversationUIState` 管理，同样独立于样式层。

#### 3.5.1 为什么需要独立的 UI 状态层

用户在样式 A 中展开了某个工具调用详情、折叠了思考过程、切换了代码块的"预览"标签——这些操作不改变对话数据，但直接影响用户体验。如果切换样式后这些状态重置，用户会感觉"记忆被清除了"。

#### 3.5.2 ConversationUIState 定义

```dart
/// 对话 UI 状态 —— 独立于样式层，切换样式时完整保留
class ConversationUIState {
  /// 已展开的工具调用 ID 集合
  final Set<String> expandedToolCallIds;

  /// 已折叠的思考过程 ID 集合
  final Set<String> collapsedThinkingIds;

  /// 已展开的代码块 ID 集合（默认折叠长代码）
  final Set<String> expandedCodeBlockIds;

  /// 当前激活的产物 Tab（canvas 样式用）
  final String? activeArtifactTab;

  /// 当前激活的上下文面板 Tab（contextPanel 样式用）
  final ContextPanelTab activeContextPanelTab; // files / tools / sources

  /// 对话分支中当前选中的分支 ID（threadBranching 样式用）
  final String? activeBranchId;

  /// 执行计划是否已确认（planSurface 样式用）
  final bool planConfirmed;

  /// 用户手动展开的消息 ID（默认折叠的子助手消息等）
  final Set<String> expandedMessageIds;
}
```

#### 3.5.3 工作机制

```
用户操作（点击展开工具调用）
    │
    ▼
StyleRenderer 调用 uiState.toggleToolCall(id)
    │
    ▼
ConversationUIState 更新 → 通过 uiStateStream 广播
    │
    ├───────────────────┐
    ▼                   ▼
当前样式重新渲染     切换到新样式时
                     新样式读取 uiState.currentState
                     保持相同的展开/折叠状态
```

- `ConversationUIState` 与 `ConversationDataSource` 平级，由 `ConversationView` 容器统一持有
- 样式渲染器通过 `uiState` 引用读取和修改 UI 状态
- 切换样式时，`uiState` 实例不变，新样式直接 attach

#### 3.5.4 状态持久化（可选）

- 会话内：内存持有，会话关闭后释放
- 跨会话：可选择持久化到 Hive（`conversation_ui_state_v1`），用户下次打开同一会话时恢复
- 默认只持久化 `expandedToolCallIds` 和 `collapsedThinkingIds`，避免存储膨胀

### 3.6 错误降级机制（ErrorBoundary）

> 15 种样式中任何一个渲染失败，都不能导致整个对话页面崩溃。必须有自动降级和恢复机制。

#### 3.6.1 降级策略

```
StyleRenderer.build() 执行
    │
    ├─ 正常 → 渲染样式 UI
    │
    └─ 抛异常 → ErrorBoundary 捕获
              │
              ├─ 记录错误日志（含样式名、消息 ID、异常栈）
              ├─ 自动降级到样式 01（经典气泡，最稳定）
              ├─ toast 提示："当前样式渲染异常，已切换为经典样式"
              └─ 上报崩溃统计（可选）
```

#### 3.6.2 ErrorBoundary 实现

```dart
class StyleErrorBoundary extends StatefulWidget {
  final ConversationStyle style;
  final Widget Function(BuildContext) builder;

  @override
  State<StyleErrorBoundary> createState() => _StyleErrorBoundaryState();
}

class _StyleErrorBoundaryState extends State<StyleErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      // 降级：显示经典气泡样式 + 错误提示
      return _FallbackStyle(
        error: _error,
        onRetry: _reset,
      );
    }
    try {
      return widget.builder(context);
    } catch (e, st) {
      // 同步异常捕获
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() { _error = e; _stackTrace = st; });
        _logError(widget.style, e, st);
        _showFallbackToast();
      });
      return const SizedBox.shrink();
    }
  }

  void _reset() => setState(() { _error = null; _stackTrace = null; });
}
```

#### 3.6.3 异步异常处理

- 样式内部的 `FutureBuilder` / `StreamBuilder` 错误通过 `AsyncSnapshot.error` 捕获
- 样式内部的 `GestureDetector` 回调异常通过 `FlutterError.onError` 全局捕获
- 所有异常统一走 ErrorBoundary 降级流程

#### 3.6.4 降级后的恢复

- 用户可在 toast 中点击"重试"，尝试重新渲染原样式
- 如果连续 3 次降级，自动锁定该会话为经典气泡样式，并记录到日志
- 设置页面增加"重置样式降级状态"按钮

---

## 4. 15 种样式详细定义

### 01 经典气泡式 (classicBubble)

| 属性 | 值 |
|---|---|
| 布局 | 用户右对齐，助手左对齐，圆角气泡 |
| 头像 | 显示 |
| 时间戳 | 显示（hover/长按） |
| 工具调用 | 内联 chip，成功/执行中状态 |
| 代码块 | 语法高亮 + 复制按钮 |
| 适用场景 | 日常聊天、短对话 |
| 信息密度 | 低 |

### 02 全宽文档式 (fullWidthDocument)

| 属性 | 值 |
|---|---|
| 布局 | 消息占满宽度，无气泡边框，分隔线区分 |
| 头像 | 角色标签代替 |
| 时间戳 | 不显示 |
| 工具调用 | 折叠引用 |
| 代码块 | 语法高亮 + 复制 + 运行按钮 |
| 适用场景 | 长文本、代码密集、文档生成 |
| 信息密度 | 中高 |

### 03 极简流式 (minimalStream)

| 属性 | 值 |
|---|---|
| 布局 | 纯文本流，无气泡无边框 |
| 头像 | 不显示 |
| 时间戳 | 不显示 |
| 工具调用 | 不显示（或极简状态行） |
| 代码块 | 等宽字体，无装饰 |
| 适用场景 | 快速问答、实时流式输出 |
| 信息密度 | 最低 |

### 04 卡片堆叠式 (cardStack)

| 属性 | 值 |
|---|---|
| 布局 | 每条消息是带阴影的卡片，视觉层次分明 |
| 头像 | 卡片头部显示 |
| 时间戳 | 卡片副标题 |
| 工具调用 | 卡片内嵌 |
| 代码块 | 卡片内代码区 |
| 适用场景 | 文件分享、图片密集、视觉驱动 |
| 信息密度 | 中 |

### 05 Agent 三层级 (agentThreeTier) ⭐ 推荐

| 属性 | 值 |
|---|---|
| 布局 | 三级视觉层级 |
| Primary | 用户消息 + 助手最终回答（全宽醒目） |
| Secondary | 子助手结果（紧凑弱化） |
| Tertiary | 工具调用/思考（内联 chip，默认折叠） |
| 工具调用 | 可折叠分组，显示工具名/参数/耗时/结果 |
| 思考过程 | 可展开块，显示 token 消耗 |
| 人工确认 | 高风险操作显示确认卡片 |
| 适用场景 | Agent 多工具调用、复杂任务 |
| 信息密度 | 高（可折叠） |

### 06 工具卡片流 (toolCardFlow)

| 属性 | 值 |
|---|---|
| 布局 | 每个工具调用是独立卡片，纵向时间线 |
| 状态 | 输入→执行中→输出实时更新 |
| 进度 | 步骤时间线（已完成/进行中/待执行） |
| 错误处理 | 失败显示红色 + 重试/跳过按钮 |
| 暂停/恢复 | 支持 |
| 适用场景 | 复杂多步骤工作流、可观测性要求高 |
| 信息密度 | 最高 |

### 07 思考-行动-观察闭环 (thinkActObserve)

| 属性 | 值 |
|---|---|
| 布局 | 左侧 rail 时间线，三阶段明确区分 |
| 思考 | 可展开，显示 token 消耗 |
| 行动 | 工具调用，显示参数校验状态 |
| 观察 | 结果分析，显示质量评分 |
| 人工确认 | 高风险节点有确认/取消 |
| 适用场景 | 深度推理、可解释性要求高 |
| 信息密度 | 高 |

### 08 终端风格 (terminal)

| 属性 | 值 |
|---|---|
| 布局 | 等宽字体，命令行风格 |
| 用户输入 | `>` 前缀 |
| 助手输出 | `~` 前缀 |
| 工具调用 | 命令执行 + spinner + 输出 |
| 代码块 | 原生终端样式 |
| 适用场景 | 开发者、代码执行、CLI 集成 |
| 信息密度 | 中高 |

### 09 多助手协作 (multiAssistant)

| 属性 | 值 |
|---|---|
| 布局 | 不同助手用颜色编码 + 名称标签 |
| 角色区分 | 研究员(蓝)/编码员(黄)/评审员(红)等 |
| 交接 | 任务交接动画 |
| 适用场景 | 多 Agent 协作、团队讨论 |
| 信息密度 | 中 |

### 10 富内容渲染 (richContent)

| 属性 | 值 |
|---|---|
| 布局 | 综合渲染，按内容类型自适应 |
| 代码块 | 语言标签 + 复制 + 预览 |
| 文件卡片 | 可预览标记 |
| 数据表格 | 原生渲染 |
| 适用场景 | 内容类型多样、综合展示 |
| 信息密度 | 中高 |

### 11 生成式 UI (generativeUi) ⭐ 推荐

| 属性 | 值 |
|---|---|
| 布局 | 模型返回交互式组件而非纯文本 |
| 组件类型 | 图表、表格、KPI 卡片、表单、diff 视图 |
| 交互 | 组件可直接操作（筛选、排序、输入） |
| 适用场景 | 数据分析、报表生成、表单填充 |
| 信息密度 | 高（结构化） |

### 12 对话分支 (threadBranching)

| 属性 | 值 |
|---|---|
| 布局 | 从某条消息分叉出多个路径 |
| 分支管理 | 标签切换、分支对比、合并主干 |
| 视觉 | 分支连接线、当前分支高亮 |
| 适用场景 | 创意写作、方案对比、头脑风暴 |
| 信息密度 | 中 |

### 13 上下文面板 (contextPanel)

| 属性 | 值 |
|---|---|
| 布局 | 对话 + 右侧固定上下文面板 |
| 面板内容 | 已上传文件、已启用工具、当前模型、引用来源 |
| 交互 | 上下文项可展开/移除 |
| 适用场景 | 多文档任务、研究、复杂上下文 |
| 信息密度 | 高 |

### 14 执行计划面板 (planSurface)

| 属性 | 值 |
|---|---|
| 布局 | Agent 先展示执行计划，用户审核后执行 |
| 计划结构 | 步骤列表 + 子任务 + 预估耗时 |
| 交互 | 确认执行 / 修改计划 / 暂停 / 恢复 |
| 进度 | 实时更新，已完成打勾 |
| 适用场景 | 复杂任务、高风险操作、需要用户确认 |
| 信息密度 | 高 |

### 15 画布产物 (canvasArtifact)

| 属性 | 值 |
|---|---|
| 布局 | 对话 + 画布并排（或上下） |
| 画布内容 | 代码预览、文档渲染、设计稿、网页 |
| 交互 | 预览/代码切换、实时编辑、下载 |
| 适用场景 | 代码生成、文档写作、设计创作 |
| 信息密度 | 高（双区） |

---

## 5. StyleResolver（样式解析器）

### 5.1 解析流程

```
用户输入消息
    │
    ▼
┌─────────────────┐
│ 检查用户手动选择  │── 有手动选择 → 直接使用
└────────┬────────┘
         │ 无（自动模式）
         ▼
┌─────────────────┐
│ 检查 per-conv 覆盖│── 有覆盖 → 使用
└────────┬────────┘
         │ 无
         ▼
┌─────────────────┐
│ 检查 per-assistant 覆盖│── 有覆盖 → 使用
└────────┬────────┘
         │ 无
         ▼
┌─────────────────┐
│ 意图识别         │
│ - 消息类型分析    │
│ - 工具调用统计    │
│ - 助手类型判断    │
│ - 风险等级评估    │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 样式匹配评分     │
│ 每种样式计算匹配度 │
│ 取最高分         │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 结果缓存         │
│ 同一会话内缓存    │
│ 避免频繁切换      │
└─────────────────┘
```

### 5.2 意图识别规则

```dart
class ConversationIntent {
  final bool hasToolCalls;
  final int toolCallCount;
  final bool hasCodeBlocks;
  final double codeBlockRatio;
  final bool hasAttachments;
  final bool hasMultipleAssistants;
  final bool hasHighRiskActions;
  final bool isCreativeTask;
  final bool isAnalyticalTask;
  final bool isDeveloperContext;
  final int messageCount;
  final double avgMessageLength;
}
```

### 5.3 样式匹配评分表

| 意图特征 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 纯文本短对话 | 3 | 1 | 3 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| 长文本/代码 | 1 | 3 | 1 | 1 | 1 | 0 | 1 | 2 | 0 | 2 | 1 | 0 | 1 | 0 | 2 |
| 工具调用 1-2 次 | 2 | 1 | 0 | 1 | 3 | 1 | 2 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| 工具调用 3+ 次 | 0 | 0 | 0 | 0 | 3 | 3 | 2 | 1 | 0 | 1 | 0 | 0 | 1 | 2 | 0 |
| 多助手 | 0 | 0 | 0 | 0 | 2 | 1 | 1 | 0 | 3 | 1 | 0 | 0 | 0 | 0 | 0 |
| 高风险操作 | 0 | 0 | 0 | 0 | 2 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 |
| 数据分析 | 0 | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 2 | 3 | 0 | 2 | 1 | 1 |
| 创意/生成 | 1 | 2 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 3 | 0 | 0 | 3 |
| 开发者场景 | 0 | 2 | 1 | 0 | 1 | 2 | 1 | 3 | 0 | 1 | 0 | 0 | 0 | 0 | 2 |
| 文件/图片密集 | 1 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 2 | 0 | 0 |
| 多文档研究 | 0 | 1 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 1 | 1 | 0 | 3 | 2 | 0 |

> 评分：3=强烈推荐，2=适合，1=可用，0=不推荐

### 5.4 切换防抖

- 同一会话内，样式切换有 **30 秒冷却期**，避免频繁切换
- 切换后显示 toast 提示："已切换为 XX 样式，点击可修改"
- 用户手动切换后，该会话锁定为手动选择，不再自动切换（除非用户重置）

---

## 6. 设置页面交互设计

### 6.1 入口

- 设置 → 通用 → 对话流样式
- 对话页面右上角菜单 → 切换样式（快捷入口）

### 6.2 设置页面布局

```
┌─────────────────────────────────────┐
│  对话流样式                          │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ ○ 自动模式                    │  │
│  │   根据对话内容智能选择最优样式  │  │
│  │   [智能推荐说明]               │  │
│  ├───────────────────────────────┤  │
│  │ ○ 手动选择                    │  │
│  │                               │  │
│  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ │  │
│  │  │ 01 │ │ 02 │ │ 03 │ │ 04 │ │  │
│  │  │预览│ │预览│ │预览│ │预览│ │  │
│  │  └────┘ └────┘ └────┘ └────┘ │  │
│  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ │  │
│  │  │ 05 │ │ 06 │ │ 07 │ │ 08 │ │  │
│  │  │预览│ │预览│ │预览│ │预览│ │  │
│  │  └────┘ └────┘ └────┘ └────┘ │  │
│  │  ... (15个)                   │  │
│  └───────────────────────────────┘  │
│                                     │
│  高级设置                           │
│  ├─ 按助手设置默认样式 [管理]        │
│  ├─ 样式切换动画 [开/关]             │
│  └─ 重置为自动模式                  │
└─────────────────────────────────────┘
```

### 6.3 快捷切换

对话页面右上角增加样式切换按钮：
- 点击弹出底部 Sheet，显示当前样式 + 15 种样式列表
- 每种样式有名称 + 一句话描述
- 选中后即时切换，有过渡动画
- 顶部有"自动模式"开关

---

## 7. 性能优化策略

### 7.1 按需加载

```dart
// 样式渲染器 lazy load
class StyleRendererRegistry {
  final Map<ConversationStyle, Lazy<StyleRenderer>> _renderers = {};

  StyleRenderer get(ConversationStyle style) {
    return _renderers[style]!.value; // 首次访问时才实例化
  }
}
```

- 核心样式（01/02/05）打包进首屏
- 其余 12 种样式使用 deferred import，按需加载
- 预估首屏体积增加 < 5%

### 7.2 渲染优化

- 样式切换时保留已渲染的消息 part，只更换外层容器
- 使用 `GlobalKey` 保持滚动位置
- 长列表使用 `ListView.builder` 懒加载
- 代码块/图片使用缓存

### 7.3 内存管理

- 未使用的样式渲染器可被 GC 回收
- 切换样式后，旧样式的渲染缓存保留 5 分钟（方便快速切回）
- 内存紧张时主动清理

---

## 8. 分阶段落地计划

### 8.0 渐进式迁移路径（双轨并行，零风险）

> 不做"大爆炸式重构"。先抽数据层，再包样式层，最后加切换能力。每一步可独立验证、可回滚。

```
Step 1: 抽数据层（不改变 UI）
  现有对话页面 → 提取 ConversationDataSource
  验证：功能完全不变，所有测试通过

Step 2: 包样式层（经典气泡作为 Style 01）
  现有气泡 UI → 包装为 ClassicBubbleRenderer
  验证：视觉完全一致，像素级对比

Step 3: 加切换能力（内部开关，用户不可见）
  增加 StyleSwitcher + StyleResolver 基础版
  验证：内部 flag 可切换，默认仍为 Style 01

Step 4: 新增样式（灰度发布）
  实现 Style 02 / Style 05
  验证：小范围用户测试，收集反馈

Step 5: 全量开放
  设置页面增加样式选择
  验证：全量用户可用
```

**每一步的回滚策略**：
- Step 1-2：回滚 = 恢复旧代码（功能完全等价）
- Step 3：回滚 = 关闭内部 flag（用户无感知）
- Step 4：回滚 = 隐藏新样式入口（默认经典气泡）
- Step 5：回滚 = 设置页隐藏切换入口（默认经典气泡）

### Phase 1：架构搭建 + 核心 3 样式（预计 2 周）

**目标**：验证架构可行性，覆盖 80% 日常场景

- [ ] 定义 `MessagePart` 统一数据模型
- [ ] 实现 `ConversationStyle` 枚举 + `StyleSettings` 持久化
- [ ] 实现 `StyleResolver` 基础版（规则匹配）
- [ ] 实现 `StyleRenderer` 接口 + Registry
- [ ] 实现样式 01（经典气泡）— 现有样式迁移
- [ ] 实现样式 02（全宽文档）
- [ ] 实现样式 05（Agent 三层级）— 重点
- [ ] 设置页面：自动/手动切换
- [ ] 对话页快捷切换入口
- [ ] 单元测试：Resolver 规则 + 数据模型

### Phase 2：扩展到 8 种样式（预计 2 周）

- [ ] 实现样式 03（极简流式）
- [ ] 实现样式 04（卡片堆叠）
- [ ] 实现样式 06（工具卡片流）
- [ ] 实现样式 08（终端风格）
- [ ] 实现样式 10（富内容渲染）
- [ ] StyleResolver 增强：意图识别 + 评分
- [ ] per-assistant / per-conversation 覆盖
- [ ] 样式切换过渡动画
- [ ] 性能优化：deferred import

### Phase 3：全量 15 种 + 智能推荐（预计 3 周）

- [ ] 实现样式 07（思考-行动-观察）
- [ ] 实现样式 09（多助手协作）
- [ ] 实现样式 11（生成式 UI）
- [ ] 实现样式 12（对话分支）
- [ ] 实现样式 13（上下文面板）
- [ ] 实现样式 14（执行计划面板）
- [ ] 实现样式 15（画布产物）
- [ ] StyleResolver 机器学习优化（基于用户切换行为）
- [ ] 样式使用统计 + A/B 测试框架
- [ ] 全量 E2E 测试

### Phase 4：生态建设（持续）

- [ ] 样式市场：支持第三方样式包
- [ ] 样式编辑器：可视化自定义样式
- [ ] 社区样式分享
- [ ] 样式模板：按行业/场景预设

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 15 种样式维护成本高 | 开发/测试资源不足 | Phase 1 先做 3 种，验证后再扩展；建立样式测试模板 |
| 样式切换性能问题 | 用户体验差 | 保留已渲染 part，只换容器；deferred import |
| 自动模式判断不准 | 用户频繁手动切换 | 收集切换行为数据，持续优化 Resolver；提供"为什么选这个样式"的解释 |
| 数据模型不统一 | 部分样式无法渲染 | Phase 1 严格定义 MessagePart，所有样式必须基于此模型 |
| 移动端性能受限 | 复杂样式卡顿 | 移动端默认简化模式，复杂样式桌面端优先 |

---

## 10. 与现有系统的集成

### 10.1 现有消息模型迁移

当前 `Message` 模型需要重构为 `Message + List<MessagePart>`：
- 现有 `content` 字段迁移为 `TextPart`
- 现有 `toolCalls` 迁移为 `ToolCallPart`
- 现有 `images` 迁移为 `ImagePart`
- 数据库迁移：新增 `parts` 字段，旧字段保留兼容

### 10.2 现有对话页面改造

- 提取 `ConversationView` 为容器，内部根据样式选择 Renderer
- 输入框、发送按钮等公共组件保持不变
- 现有气泡样式迁移为 Style 01

### 10.3 与 Agent 系统集成

- Agent 执行事件（tool_call_start / tool_call_end / thinking）统一转为 `ToolCallPart` / `ThinkingPart`
- 高风险操作触发 `ApprovalPart`
- 多助手协作通过 `assistantId` 区分

### 10.4 测试策略与统一测试数据集

#### 10.4.1 统一测试数据集（Golden Dataset）

> 所有 15 种样式使用**同一份**测试数据，确保切换样式时数据完全一致。这也是演示应用的核心设计——用户看到的是同一段对话在不同样式下的真实渲染效果。

**数据集构成**（1 个完整会话，8 条消息，覆盖所有 MessagePart 类型）：

| # | 角色 | 内容类型 | 包含的 Part |
|---|---|---|---|
| 1 | user | 文本+附件 | TextPart + FilePart（PDF文档） |
| 2 | assistant | 思考+工具调用 | ThinkingPart + ToolCallPart(web_search, running) |
| 3 | assistant | 工具结果+文本 | ToolCallPart(web_search, success) + TextPart |
| 4 | user | 文本 | TextPart（追问，引用消息2） |
| 5 | assistant | 多工具调用 | ToolCallPart(scrape, success) + ToolCallPart(summarize, success) + TextPart |
| 6 | assistant | 代码+审批 | CodePart(Dart) + ApprovalPart(高风险操作, pending) |
| 7 | user | 审批通过 | TextPart + ApprovalPart(approved) |
| 8 | assistant | 最终回答+产物 | TextPart + ArtifactPart(报告) + ImagePart(图表) |

**数据集文件**：`test/fixtures/conversation_style_golden.json`

#### 10.4.2 测试层级

| 测试类型 | 覆盖范围 | 工具 |
|---|---|---|
| 单元测试 | MessagePart 模型、StyleResolver 规则、DataSource 接口 | flutter test |
| Widget 测试 | 每种样式渲染 Golden Dataset 不崩溃 | flutter test |
| Golden 测试 | 每种样式的视觉截图对比 | flutter test + golden_toolkit |
| 集成测试 | 样式切换前后数据一致、状态保留 | flutter integration_test |
| 性能测试 | 切换耗时、滚动 FPS、内存占用 | flutter drive |

#### 10.4.3 样式切换集成测试用例

```dart
testWidgets('样式切换前后消息内容完全一致', (tester) async {
  // 加载 Golden Dataset
  final messages = await loadGoldenDataset();

  // 用样式 01 渲染
  await tester.pumpWidget(ConversationView(style: Style.classicBubble, data: messages));

  // 记录渲染出的文本内容
  final textBefore = findAllText(tester);

  // 切换到样式 05
  await tester.tap(find.byKey(StyleSwitcher.key));
  await tester.pumpAndSettle();

  // 验证文本内容完全一致
  final textAfter = findAllText(tester);
  expect(textAfter, equals(textBefore));
});

testWidgets('样式切换时工具调用状态保留', (tester) async {
  // 工具调用处于 running 状态时切换样式
  // 验证新样式中该工具仍显示 running 状态
});

testWidgets('样式切换时滚动位置保留', (tester) async {
  // 滚动到中间位置，切换样式，验证 scroll offset 不变
});
```

---

## 11. 验收标准

### Phase 1 验收

- [ ] 3 种样式可正常渲染相同对话数据
- [ ] 样式切换无数据丢失、无明显卡顿
- [ ] 自动模式能根据简单规则选择样式
- [ ] 设置页面可切换自动/手动
- [ ] 单元测试覆盖率 > 80%
- [ ] flutter analyze 0 error / 0 warning

### 全量验收

- [ ] 15 种样式全部实现
- [ ] 自动模式在 10 种典型场景下选择合理（人工评估）
- [ ] 样式切换过渡动画流畅（60fps）
- [ ] 首屏体积增加 < 10%
- [ ] 内存占用增加 < 15%
- [ ] 全量 E2E 测试通过

---

## 附录 A：术语表

| 术语 | 定义 |
|---|---|
| MessagePart | 消息的最小组成单元（文本/代码/工具调用/图片等） |
| StyleRenderer | 样式渲染器，将 MessagePart 渲染为具体 UI |
| StyleResolver | 样式解析器，根据上下文选择最优样式 |
| ConversationIntent | 对话意图，描述当前对话的特征向量 |
| Progressive Disclosure | 渐进式披露，默认显示摘要，按需展开细节 |
| Artifact | 产物，助手生成的可交互/可编辑内容（代码/文档/设计） |

## 附录 B：参考资料

- Vercel AI SDK - Generative UI
- AG-UI Protocol - Agent-User Interaction Protocol
- LangGraph GenUI - Tool Call Visualization
- Agentic UI (antdigital-ai) - 思考-行动-观察闭环
- ChatGraPhT - 可视化对话地图
- OpenAI ChatKit - Tool Call Rendering
- Claude Artifacts - Canvas/Artifact Pattern
