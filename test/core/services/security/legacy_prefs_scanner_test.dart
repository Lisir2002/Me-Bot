import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/checkup_scanner.dart';
import 'package:minime_core/core/services/security/scanners/legacy_prefs_scanner.dart';
import 'package:minime_core/core/services/security/credential_audit_logger.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';

/// P2-5：一键修复（LegacyPrefsScanner.autoFix）的回归测试。
///
/// 核心防回归断言：即使触发一键修复，仍在使用的配置 key
/// （provider / search / tts / webdav）绝不被删除。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => CredentialAuditLogger.resetForTest());

  group('LegacyPrefsScanner 一键修复', () {
    test('一键修复后 provider 配置不丢失，纯明文残留被删', () async {
      const providerJson =
          '{"openai":{"id":"openai","name":"OpenAI","baseUrl":"https://api.openai.com/v1"}}';
      SharedPreferences.setMockInitialValues({
        // 仍在使用的配置（已剥离凭证）—— 必须保留
        CredentialKeys.legacyProviderConfigs: providerJson,
        CredentialKeys.legacySearchServices: '[{"id":"google","name":"Google"}]',
        CredentialKeys.legacyTtsServices: '[{"id":"edge","name":"Edge"}]',
        // 真·纯明文残留 —— 应被删除
        CredentialKeys.legacyGlobalProxyUsername: 'proxy-user',
      });
      final prefs = await SharedPreferences.getInstance();
      final scanner = LegacyPrefsScanner(prefs);

      final findings = await scanner.scan(_FakeStrings());
      final legacyFinding =
          findings.where((f) => f.id == 'legacy_prefs:legacy_keys').toList();
      expect(legacyFinding.length, 1, reason: '应只发现纯明文残留一条 danger');

      final ok = await scanner.autoFix(legacyFinding.first);
      expect(ok, isTrue);

      // 仍在使用的配置完好
      expect(prefs.getString(CredentialKeys.legacyProviderConfigs), providerJson);
      expect(prefs.containsKey(CredentialKeys.legacySearchServices), isTrue);
      expect(prefs.containsKey(CredentialKeys.legacyTtsServices), isTrue);
      // 纯明文残留被删
      expect(prefs.containsKey(CredentialKeys.legacyGlobalProxyUsername), isFalse);
    });

    test('白名单拦截：即使把 active key 塞进删除列表也拒绝删除', () async {
      const providerJson = '{"openai":{"id":"openai"}}';
      SharedPreferences.setMockInitialValues({
        // 故意把 active 配置 key 注入待删列表（模拟未来有人误加回）
        'provider_configs_v1': providerJson,
        CredentialKeys.legacyGlobalProxyUsername: 'proxy-user',
      });
      final prefs = await SharedPreferences.getInstance();
      // 注入 deletableKeys：包含一个白名单 key + 一个真残留 key
      final scanner = LegacyPrefsScanner(
        prefs,
        deletableKeys: const [
          'provider_configs_v1',
          CredentialKeys.legacyGlobalProxyUsername,
        ],
      );

      final findings = await scanner.scan(_FakeStrings());
      final legacyFinding =
          findings.where((f) => f.id == 'legacy_prefs:legacy_keys').toList();
      expect(legacyFinding.length, 1);

      final ok = await scanner.autoFix(legacyFinding.first);
      // 真残留被删 → 返回 true；白名单 key 被拦截
      expect(ok, isTrue);
      expect(prefs.containsKey(CredentialKeys.legacyGlobalProxyUsername), isFalse);
      expect(prefs.getString('provider_configs_v1'), providerJson,
          reason: '白名单 key 必须被拒绝删除');
    });

    test('webdav_config_v1 永远不会被自动删除', () async {
      const webdavJson = '{"url":"https://dav.example.com/dav","path":"/bk"}';
      SharedPreferences.setMockInitialValues({
        'webdav_config_v1': webdavJson,
        CredentialKeys.legacyGlobalProxyPassword: 'plain-pw',
      });
      final prefs = await SharedPreferences.getInstance();
      // 即使有人把 webdav_config_v1 误加入待删列表
      final scanner = LegacyPrefsScanner(
        prefs,
        deletableKeys: const ['webdav_config_v1'],
      );
      final findings = await scanner.scan(_FakeStrings());
      final legacyFinding =
          findings.where((f) => f.id == 'legacy_prefs:legacy_keys').toList();
      expect(legacyFinding.length, 1);

      await scanner.autoFix(legacyFinding.first);
      expect(prefs.getString('webdav_config_v1'), webdavJson,
          reason: 'webdav_config_v1 仍承载非敏感配置，不能删');
    });
  });
}

class _FakeStrings implements CheckupStrings {
  @override
  String scannerErrorTitle(String scannerTitle) => 'err:$scannerTitle';
  @override
  String scannerErrorDetail() => 'd';
  @override
  String backupPlaintextTitle(int count) => 't:$count';
  @override
  String backupPlaintextDetail(List<String> files) => 'd:${files.length}';
  @override
  String legacyKeysTitle() => 'legacy keys';
  @override
  String legacyKeysDetail(int count, List<String> keys) => 'd:$count';
  @override
  String legacyKeysFixHint() => 'h';
  @override
  String legacyPlaintextTitle() => 't';
  @override
  String legacyPlaintextDetail(int suspectCount) => 'd:$suspectCount';
  @override
  String logLeakTitle() => 't';
  @override
  String logLeakDetail(int files, int lines) => 'd:$files/$lines';
  @override
  String orphanTitle(int count) => 't:$count';
  @override
  String orphanDetail() => 'd';
  @override
  String orphanFixHint() => 'h';
}
