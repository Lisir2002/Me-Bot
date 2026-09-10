# MiniMe-Core

> 一个开源、本地优先的 AI 聊天客户端，基于 Flutter 构建。

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Tb8DyvvV5T)
[![QQ Group](https://img.shields.io/badge/QQ%20Group-0366CC?style=flat&logo=tencentqq&logoColor=white)](https://qm.qq.com/q/OQaXetKssC)

[English](README.md) | 简体中文

## 项目简介

MiniMe-Core 是一个跨平台 AI 助手客户端，可接入主流大模型供应商，
支持自定义助手、多模态输入、MCP 工具集成、联网搜索与本地数据备份。
界面采用统一设计系统（iOS 风格分组卡片）并支持动态主题。

## 功能特性

- **现代化设计** — Material You 动态主题色（Android 12+）
- **深色模式** — 完整适配
- **多语言** — 简体中文 / 英文（更多语言经 l10n 扩展）
- **多平台** — Android、iOS、HarmonyOS、Windows、macOS、Linux
- **多供应商** — OpenAI、Google Gemini、Anthropic 等
- **自定义助手** — 创建并管理个性化 AI 助手
- **多模态输入** — 图片、文档、PDF、Word 等
- **Markdown 渲染** — 代码高亮、LaTeX 公式、表格
- **语音服务** — 系统 TTS + OpenAI / Gemini / ElevenLabs
- **MCP 支持** — Model Context Protocol 工具集成，内置 Fetch 工具
- **联网搜索** — Exa、Tavily、知谱、LinkUp、Brave、Bing、Metaso、SearXNG 等
- **提示词变量** — 模型名称、时间等动态变量
- **二维码分享** — 通过二维码导入导出供应商配置
- **数据备份** — 聊天记录备份与恢复
- **自定义请求** — 自定义 HTTP 请求头与请求体
- **自定义字体** — 系统字体 / Google Fonts
- **后台生成** — Android 后台持续生成对话（设置中开启）

## 平台支持

| 平台       | 状态 |
|------------|------|
| Android    | ✅   |
| iOS        | ✅   |
| HarmonyOS  | ✅ ([Me-Bot-ohos](https://github.com/Lisir2002/Me-Bot-ohos)) |
| Windows    | ✅   |
| macOS      | ✅   |
| Linux      | ✅   |

## 文档

- [设计系统](docs/design/design-system.md) — 组件映射与强制约定
- [存储与备份设计](docs/design/storage-feature-design.md)
- [UI 骨架迁移计划](docs/design/ui-skeleton-migration-plan.md)
- [Warning 清零规划](docs/design/warning-clearance.md)
- [架构概览](docs/architecture/overview.md)
- [审计待办](docs/architecture/action-items.md)
- [版本规范](docs/versioning.md)
- [AI 代理指南 (AGENTS.md)](AGENTS.md)

## 架构

分层 Flutter 架构：

- `lib/features/*` — 功能模块（界面 + 状态）
- `lib/core/*` — 服务层（安全存储、备份加密、MCP、统计）
- `lib/shared/*` — 共享组件与设计系统原语（`AppPage`、`AppSectionCard`、`AppNavRow`、`AppSwitchRow`、`showAppSnackBar`）
- `lib/theme/*` — 设计令牌（`AppStatusColor`、圆角、字体）

所有页面走统一设计系统；`Scaffold` / `SnackBar` / `ListTile` 被 lint 拦截
（`tools/l10n_lints`）。本地化三语（en / zh / zh_Hant）并带防漏译护栏。

## 快速开始

### 环境要求

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.35+
- Dart 3.9+
- 各平台工具链：Android Studio / Xcode / Visual Studio

### 安装

```bash
git clone https://github.com/Lisir2002/Me-Bot.git
cd Me-Bot
flutter pub get
```

### 运行

```bash
flutter run
flutter run -d android
flutter run -d ios
```

### 测试

```bash
flutter test
```

### 构建

```bash
flutter build apk --release
flutter build ios --release
flutter build windows --release
```

## 下载

最新 Android 构建见 [GitHub Releases](https://github.com/Lisir2002/Me-Bot/releases/latest)。
测试版可经 [TestFlight](https://testflight.apple.com/join/PZZyRMyY) 体验。

## 贡献指南

欢迎提交 Pull Request 或 Issue！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/your-feature`)
3. 提交更改 (`git commit -m 'Add some feature'`)
4. 推送分支 (`git push origin feature/your-feature`)
5. 开启 Pull Request

## 致谢

- 界面设计深受 [RikkaHub](https://github.com/re-ovo/rikkahub) 启发
- 感谢 [siliconflow.cn](https://siliconflow.cn) 提供可免费使用的模型

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Lisir2002/Me-Bot&type=Date)](https://star-history.com/#Lisir2002/Me-Bot&Date)

## 许可证

本项目采用 [AGPL-3.0](LICENSE) 许可证。
