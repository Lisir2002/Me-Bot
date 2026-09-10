# MiniMe-Core

> An open-source, local-first AI chat client built with Flutter.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Tb8DyvvV5T)
[![QQ Group](https://img.shields.io/badge/QQ%20Group-0366CC?style=flat&logo=tencentqq&logoColor=white)](https://qm.qq.com/q/OQaXetKssC)

English | [简体中文](README_ZH_CN.md)

## Overview

MiniMe-Core is a cross-platform AI assistant client. It connects to mainstream
LLM providers, supports custom assistants, multimodal input, MCP tool
integration, web search, and local data backup. The UI follows a unified design
system (iOS-style grouped cards) with dynamic theming.

## Features

- **Modern design** — Material You with dynamic color theming (Android 12+).
- **Dark mode** — fully adapted dark theme.
- **Multi-language** — English and Simplified Chinese (more via l10n).
- **Multi-platform** — Android, iOS, HarmonyOS, Windows, macOS, Linux.
- **Multi-provider** — OpenAI, Google Gemini, Anthropic, and more.
- **Custom assistants** — create and manage personalized AI assistants.
- **Multimodal input** — images, documents, PDF, Word, and more.
- **Markdown rendering** — code highlighting, LaTeX, tables.
- **Voice / TTS** — system TTS plus OpenAI / Gemini / ElevenLabs.
- **MCP support** — Model Context Protocol tool integration with a built-in Fetch tool.
- **Web search** — Exa, Tavily, Zhipu, LinkUp, Brave, Bing, Metaso, SearXNG, and more.
- **Prompt variables** — dynamic variables (model name, time, …).
- **QR-code sharing** — export/import provider configs via QR codes.
- **Data backup** — chat history backup and restore.
- **Custom requests** — custom HTTP headers and bodies.
- **Custom fonts** — system fonts / Google Fonts.
- **Background generation** — keep chat generation running in the background (Android).

## Platform Support

| Platform   | Status |
|------------|--------|
| Android    | ✅     |
| iOS        | ✅     |
| HarmonyOS  | ✅ ([Me-Bot-ohos](https://github.com/Lisir2002/Me-Bot-ohos)) |
| Windows    | ✅     |
| macOS      | ✅     |
| Linux      | ✅     |

## Documentation

- [Design System](docs/design/design-system.md) — component map & mandatory UI conventions
- [Storage & Backup Design](docs/design/storage-feature-design.md)
- [UI Skeleton Migration Plan](docs/design/ui-skeleton-migration-plan.md)
- [Warning Clearance Plan](docs/design/warning-clearance.md)
- [Architecture Overview](docs/architecture/overview.md)
- [Audit Action Items](docs/architecture/action-items.md)
- [Versioning](docs/versioning.md)
- [AI Agent Guide (AGENTS.md)](AGENTS.md)

## Architecture

Layered Flutter architecture:

- `lib/features/*` — feature modules (UI + state)
- `lib/core/*` — services (secure storage, backup crypto, MCP, stats)
- `lib/shared/*` — shared widgets & design-system primitives (`AppPage`, `AppSectionCard`, `AppNavRow`, `AppSwitchRow`, `showAppSnackBar`)
- `lib/theme/*` — design tokens (`AppStatusColor`, radius, typography)

All screens go through the shared design system; raw `Scaffold` / `SnackBar` /
`ListTile` are lint-blocked by `tools/l10n_lints`. Localization is three-way
(en / zh / zh_Hant) with a no-missing-translation guard.

## Project Structure

```
lib/                 Application source (features / shared / theme / core)
android/             Android engine
ios/                 iOS engine
web/                 Web engine
linux/ macos/ windows/   Desktop engines
assets/              App icon, provider SVGs, mermaid runtime, html templates
dependencies/        Vendored path dependencies (e.g. flutter_tts)
docs/                Design system, architecture, versioning
tools/               l10n guards, custom_lint plugin
test/                Tests
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.35+
- Dart 3.9+
- Platform toolchains: Android Studio / Xcode / Visual Studio (per target)

### Installation

```bash
git clone https://github.com/Lisir2002/Me-Bot.git
cd Me-Bot
flutter pub get
```

### Run

```bash
flutter run             # default platform
flutter run -d android
flutter run -d ios
```

### Test

```bash
flutter test
```

### Build

```bash
flutter build apk --release
flutter build ios --release
flutter build windows --release
# …and other targets
```

## Download

Get the latest Android build from the
[GitHub Releases](https://github.com/Lisir2002/Me-Bot/releases/latest) page.
Beta testing is available on [TestFlight](https://testflight.apple.com/join/PZZyRMyY).

## Contributing

Pull requests and issues are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m 'Add some feature'`)
4. Push to the branch (`git push origin feature/your-feature`)
5. Open a Pull Request

## Acknowledgements

- UI design inspired by [RikkaHub](https://github.com/re-ovo/rikkahub).
- Thanks to [siliconflow.cn](https://siliconflow.cn) for providing free models.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Lisir2002/Me-Bot&type=Date)](https://star-history.com/#Lisir2002/Me-Bot&Date)

## License

Licensed under the [AGPL-3.0](LICENSE) license.
