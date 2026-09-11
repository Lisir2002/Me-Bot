import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../logging/logger.dart';
import '../logging/log_tags.dart';
import 'app_lock_gate.dart';

/// local_auth 实现的身份校验器（预留接口⑤ 首个实现，PR-6）。
///
/// 生物识别优先；系统在无生物识别时会自动回退到设备 PIN/图案/密码
/// （`deviceAuthAllowed`）。local_auth 自身保证这一回退。
class LocalIdentityVerifier implements IdentityVerifier {
  LocalIdentityVerifier({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String localizedReason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false, // 允许回退系统 PIN/密码
          stickyAuth: true,
        ),
      );
      if (ok) {
        Logger.i(LogTags.lock, 'biometric auth success');
      } else {
        Logger.w(LogTags.lock, 'biometric auth failed: reason=returned_false');
      }
      return ok;
    } on PlatformException catch (e) {
      // 用户取消 / 系统取消 → debug 级，其他异常 → warn 级
      if (e.code == 'user_cancelled' || e.code == 'auth_cancelled') {
        Logger.d(LogTags.lock, 'biometric auth cancelled');
      } else {
        Logger.w(LogTags.lock, 'biometric auth failed: reason=${e.code}', e);
      }
      return false;
    } catch (e) {
      Logger.w(LogTags.lock, 'biometric auth failed: reason=unknown', e);
      return false;
    }
  }

  @override
  String get methodName => '生物识别 / 设备 PIN';
}
