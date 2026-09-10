# 版本号与发布规范

本仓库的版本管理必须遵循以下规则。任何发布（App 更新 / GitHub Release / CI 部署）均以此为准。

## 1. 版本号格式

Flutter 的 `pubspec.yaml` 只支持**三段语义化版本 + 构建号**：

```
MAJOR.MINOR.PATCH+buildCode
```

- **MAJOR.MINOR.PATCH**：语义化版本（当前从 `0.0.0` 起步）。
- **buildCode**：构建号，从 `1` 开始，每次发布**只增不减**。
  - Android 用它作为 `versionCode`（用于应用商店同一包名的强制升级判定）。
  - 其他平台用它作为构建后缀 / 内部版本。

> 注意：**不允许**写四段形式（如 `0.0.0.1`），Flutter / pub / Gradle 会直接报错。
> 四段中的最后一段对应到这里的 `buildCode`。

## 2. 版本更新规则

| 变更类型 | 如何更新 | 版本示例（递增 buildCode） |
| --- | --- | --- |
| 修复 Bug | 打 **RC（预发布）版本**，不立即发正式版 | `0.0.0+1` → 修 bug → `0.0.0+2-rc.1` |
| 新增 / 减少功能 | 递增 `PATCH`，并发正式版 | `0.0.0+1` → 增功能 → `0.0.1+2` |
| 较大的破坏性改动 | 递增 `MINOR`（或 `MAJOR`），并发正式版 | 视影响面决定 |

### 3. RC（Release Candidate）规定

- **只在修复 Bug 时需要发候选版给用户/测试验证时**使用 RC。
- RC 的 tag 形如 `v0.0.0-rc.1`、`v0.0.0-rc.2`。
- RC 上传到 GitHub Release 时**必须标记为 `Prerelease`**（`draft: false, prerelease: true`）。
- 应用内"检查更新"应只提示**最新的正式版**，不得把 RC 当成正式更新推送给用户。
- 测试通过后，把 RC 合入正式版：版本号保留为目标正式版（如 `0.0.0+2`），发布一个非 prerelease 的 Release。

### 4. 发布流程（CI）

1. 修改 `pubspec.yaml` 的 `version:`（保持 `log` 记录本次变更）。
2. 推送到 `main`。
3. 触发 GitHub Actions 的 `build-stable.yml`：
   - 正式版：`publish_release=true`，`release_tag=v<正式版本>`。
   - RC：同上，`release_tag=v<版本>-rc.N`（CI 上传后需手动把对应 Release 标记为 Prerelease）。
4. 所有 APK / 安装包**必须用 release-key.jks 正式签名**（见下节），未签名的包视为无效。

## 5. 签名

- 发布用 keystore：`release-key.jks`，其内容以 **Base64** 存放在 CI Secret `SIGN_KEYSTORE_BASE64`。
- 配套 Secrets：`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`。
- ⚠️ **keystore 必须永久、离线备份**。安卓规定后续版本必须用**同一证书**签名才能升级；丢失后该包名将永远无法再发更新。
- `key.properties` 由 CI 在构建时注入，**切勿提交进仓库**。

## 6. 检查清单（发布前）

- [ ] `version:` 已按上表更新，`buildCode` 只增不减
- [ ] 是否 RC 已在 Release 页面标记为 `Prerelease`
- [ ] 安装包已用 `release-key.jks` 签名
- [ ] 应用内"检查更新"链接指向 GitHub Releases 的正确资产