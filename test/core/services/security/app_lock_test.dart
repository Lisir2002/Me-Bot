import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/app_lock_gate.dart';
import 'package:minime_core/core/services/security/app_lock_service.dart';

class _FakeVerifier implements IdentityVerifier {
  _FakeVerifier({this.supported = true, bool authResult = true})
      : _authResult = authResult;
  final bool supported;
  bool _authResult;
  int authCalls = 0;

  // 测试中途切换认证结果（模拟首次通过、后来拒绝等场景）。
  set authResult(bool v) => _authResult = v;

  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> authenticate(String localizedReason) async {
    authCalls++;
    return _authResult;
  }

  @override
  String get methodName => 'fake';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLockService.resetForTest();
  });

  test('默认关闭 → 无需认证直接放行', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 0);
  });

  test('开启需现场验证：验证通过才生效（管理动作不进入宽限期）', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    expect(await svc.setEnabled(true), isTrue);
    expect(v.authCalls, 1);
    expect(svc.enabled, isTrue);
    // 开启本身不算解锁：第一次敏感操作仍要认证
    expect(svc.withinGrace, isFalse);
  });

  test('开启验证失败 → 拒绝开启', () async {
    final v = _FakeVerifier(authResult: false);
    final svc = AppLockService(verifier: v);
    expect(await svc.setEnabled(true), isFalse);
    expect(svc.enabled, isFalse);
  });

  test('关闭也需验证：防止他人随手关掉门禁', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    v.authResult = false;
    expect(await svc.setEnabled(false), isFalse); // 验证失败 → 关不掉
    expect(svc.enabled, isTrue);
    v.authResult = true;
    expect(await svc.setEnabled(false), isTrue);
    expect(svc.enabled, isFalse);
    expect(svc.withinGrace, isFalse); // 关闭即清空解锁态
  });

  test('verify 注入：外部回调优先生效，不触发本地认证', () async {
    final v = _FakeVerifier();
    var injected = 0;
    final svc = AppLockService(verifier: v);
    expect(
      await svc.setEnabled(true, verify: () async {
        injected++;
        return true;
      }),
      isTrue,
    );
    expect(injected, 1);
    expect(v.authCalls, 0);
  });

  test('开启后敏感操作需认证；成功后进入宽限期，期内免重复认证', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    expect(await svc.ensureUnlocked(LockAction.copyCredential), isTrue);
    expect(v.authCalls, 2); // 开启 1 次 + 首个敏感操作 1 次
    expect(svc.withinGrace, isTrue);
    expect(await svc.ensureUnlocked(LockAction.copyCredential), isTrue);
    expect(v.authCalls, 2); // 宽限期内不再认证
  });

  test('宽限期 0 → 每次敏感操作都认证', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    await svc.setGraceMinutes(0);
    expect(await svc.ensureUnlocked(LockAction.exportWithKey), isTrue);
    expect(await svc.ensureUnlocked(LockAction.exportWithKey), isTrue);
    expect(v.authCalls, 3); // 开启 1 次 + 两次操作各 1 次
  });

  test('验证失败不进入宽限期，下次仍需认证', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    v.authResult = false;
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isFalse);
    expect(svc.withinGrace, isFalse);
    v.authResult = true;
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 3); // 开启 + 失败 + 成功
  });

  test('lockNow 清空解锁态，下次敏感操作强制重新认证', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    await svc.ensureUnlocked(LockAction.viewCredential);
    expect(svc.withinGrace, isTrue);
    await svc.lockNow();
    expect(svc.withinGrace, isFalse);
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 3);
  });

  test('setGraceMinutes 会被 clamp 到 0-60', () async {
    final svc = AppLockService(verifier: _FakeVerifier());
    await svc.setGraceMinutes(-5);
    expect(svc.graceMinutes, 0);
    await svc.setGraceMinutes(999);
    expect(svc.graceMinutes, 60);
    await svc.setGraceMinutes(15);
    expect(svc.graceMinutes, 15);
  });

  test('设备不支持 → 不允许开启', () async {
    final v = _FakeVerifier(supported: false);
    final svc = AppLockService(verifier: v);
    expect(await svc.setEnabled(true), isFalse);
    expect(svc.enabled, isFalse);
  });

  test('极端兜底：已开启但设备不支持 → 放行（不阻塞主流程）', () async {
    SharedPreferences.setMockInitialValues({'lock_enabled': true});
    final v = _FakeVerifier(supported: false);
    final svc = await AppLockService.load(verifier: v);
    expect(svc.enabled, isTrue);
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 0);
  });

  test('持久化往返：开关状态与宽限期都持久化', () async {
    final svc = AppLockService(verifier: _FakeVerifier());
    await svc.setEnabled(true);
    await svc.setGraceMinutes(15);

    AppLockService.resetForTest();
    final reloaded = await AppLockService.load();
    expect(reloaded.enabled, isTrue);
    expect(reloaded.graceMinutes, 15);

    // 关闭也持久化（verify 注入绕开真实认证器；load() 内部用默认认证器，测试环境必拒）
    await reloaded.setEnabled(false, verify: () async => true);
    AppLockService.resetForTest();
    final reloaded2 = await AppLockService.load();
    expect(reloaded2.enabled, isFalse);
    expect(reloaded2.graceMinutes, 15);
  });

  test('canEnable 反映设备支持情况', () async {
    expect(
        await AppLockService(verifier: _FakeVerifier(supported: true))
            .canEnable(),
        isTrue);
    expect(
        await AppLockService(verifier: _FakeVerifier(supported: false))
            .canEnable(),
        isFalse);
  });
}
