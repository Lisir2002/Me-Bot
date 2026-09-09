import 'package:flutter/material.dart';

/// 门禁动作类别（决定哪些敏感操作需要解锁，PR-6）。
enum LockAction {
  /// 进入凭证设置 / 查看 Key。
  viewCredential,

  /// 复制 Key 到剪贴板。
  copyCredential,

  /// 加密导出（含密钥）。
  exportWithKey,

  /// 输入 JWE 口令解密备份。
  enterPassphrase,

  /// 进入隐私门禁设置。
  lockSettings,
}

/// 门禁协议（预留接口⑤）。
///
/// 首个实现 [AppLockService]（生物识别/PIN，经 [IdentityVerifier]）。
/// 未来方向：企业级 KMS/SSO 下发门禁策略、按动作/时段门禁，只需再实现本接口。
abstract class AppLockGate {
  /// 是否开启了门禁。
  bool get enabled;

  /// 设备是否支持生物识别 / PIN（不支持时 UI 应隐藏该功能）。
  Future<bool> canEnable();

  /// 若开启门禁则先校验身份，否则直接放行。
  /// [reason] 展示给用户的本地化说明（如「验证身份以查看密钥」）。
  /// 返回 true 表示允许继续；false 表示用户取消 / 校验失败。
  Future<bool> ensureUnlocked(LockAction action,
      {BuildContext? context, String? reason});
}

/// 身份校验器契约（预留接口⑤）。
///
/// 把「如何证明你是你」从门禁逻辑里抽离：当前是 local_auth（生物识别/PIN），
/// 未来鸿蒙端可另实现 [IdentityVerifier] 接系统身份验证，门禁代码零改动。
abstract class IdentityVerifier {
  /// 设备是否具备可用的生物识别 / 设备凭证（PIN/图案/密码）。
  Future<bool> isDeviceSupported();

  /// 弹出系统认证；[localizedReason] 展示给用户。成功返回 true。
  Future<bool> authenticate(String localizedReason);

  /// 当前可用的认证手段名（用于 UI 文案，如「生物识别」/「设备 PIN」）。
  String get methodName;
}
