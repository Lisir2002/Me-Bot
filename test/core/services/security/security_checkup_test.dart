import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/checkup_scanner.dart';
import 'package:minime_core/core/services/security/security_checkup_service.dart';
import 'package:minime_core/core/services/security/scanners/legacy_prefs_scanner.dart';
import 'package:minime_core/core/services/security/scanners/orphan_credential_scanner.dart';
import 'package:minime_core/core/services/security/scanners/backup_file_scanner.dart';
import 'package:minime_core/core/services/security/scanners/log_file_scanner.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';
import 'package:minime_core/core/services/secure_storage/credential_record.dart';

import '../../../helpers/fake_secure_backend.dart';

void main() {
  group('CheckupSeverity', () {
    test('max 取较高严重度', () {
      expect(CheckupSeverity.max(CheckupSeverity.safe, CheckupSeverity.warn),
          CheckupSeverity.warn);
      expect(CheckupSeverity.max(CheckupSeverity.warn, CheckupSeverity.danger),
          CheckupSeverity.danger);
    });
  });

  group('SecurityCheckupService 引擎', () {
    test('聚合多扫描器结果 + 严重度取最高', () async {
      final svc = SecurityCheckupService([
        _FakeScanner('s1', [CheckupFinding(id: 's1:a', scannerId: 's1', title: 't', detail: 'd', severity: CheckupSeverity.warn)]),
        _FakeScanner('s2', [CheckupFinding(id: 's2:a', scannerId: 's2', title: 't', detail: 'd', severity: CheckupSeverity.danger)]),
      ]);
      final report = await svc.run(_FakeStrings());
      expect(report.findings.length, 2);
      expect(report.overallSeverity, CheckupSeverity.danger);
      expect(report.dangerCount, 1);
      expect(report.warnCount, 1);
    });

    test('单扫描器异常被兜底为 warn，不拖垮整体', () async {
      final svc = SecurityCheckupService([
        _FakeScanner('boom', const [], throwsOnScan: true),
        _FakeScanner('ok', [CheckupFinding(id: 'ok:a', scannerId: 'ok', title: 't', detail: 'd', severity: CheckupSeverity.safe)]),
      ]);
      final report = await svc.run(_FakeStrings());
      expect(report.findings.any((f) => f.id == 'boom:error'), isTrue);
    });

    test('fix 仅修复 autoFixable 项', () async {
      final fixable = _FixableScanner();
      final svc = SecurityCheckupService([fixable]);
      final report = await svc.run(_FakeStrings());
      final fixed = await svc.fix(report.fixable);
      expect(fixed, 1);
      expect(fixable.fixed, isTrue);
    });
  });

  group('LegacyPrefsScanner', () {
    test('纯明文残留 key 残留 → danger 且可修复；仍在使用的配置 key 不被碰', () async {
      SharedPreferences.setMockInitialValues({
        // 真·纯明文残留（迁移后应删）：全局代理用户名
        CredentialKeys.legacyGlobalProxyUsername: 'plain-user',
        // 仍在使用的配置 key（已剥离凭证）：绝不能被一键删除
        CredentialKeys.legacyProviderConfigs: '{"openai":{"name":"OpenAI"}}',
        'unrelated_setting': 'value',
      });
      final prefs = await SharedPreferences.getInstance();
      final scanner = LegacyPrefsScanner(prefs);
      final findings = await scanner.scan(_FakeStrings());
      final danger = findings.where((f) => f.severity == CheckupSeverity.danger);
      expect(danger.length, 1);
      expect(danger.first.autoFixable, isTrue);

      expect(await scanner.autoFix(danger.first), isTrue);
      // 纯明文残留被删
      expect(prefs.containsKey(CredentialKeys.legacyGlobalProxyUsername), isFalse);
      // 仍在使用的供应商配置完好保留（回归：曾被一键修复误删）
      expect(prefs.getString(CredentialKeys.legacyProviderConfigs),
          '{"openai":{"name":"OpenAI"}}');
    });

    test('无残留 → 无发现', () async {
      SharedPreferences.setMockInitialValues({'unrelated': 'value'});
      final scanner = LegacyPrefsScanner(await SharedPreferences.getInstance());
      expect(await scanner.scan(_FakeStrings()), isEmpty);
    });
  });

  group('OrphanCredentialScanner', () {
    test('无主凭证 → warn 且 autoFix 删除', () async {
      final service = buildService(FakeBackend());
      await service.write(CredentialKeys.provider('gone'), CredentialRecord.create(type: CredentialType.apiKey, value: 'v').encode());
      await service.write(CredentialKeys.provider('alive'), CredentialRecord.create(type: CredentialType.apiKey, value: 'v').encode());

      final scanner = OrphanCredentialScanner(
        service,
        knownProviderIds: {'alive'},
        knownServiceIds: const {},
      );
      final findings = await scanner.scan(_FakeStrings());
      expect(findings.length, 1);
      expect(findings.first.autoFixable, isTrue);

      expect(await scanner.autoFix(findings.first), isTrue);
      expect(await service.contains(CredentialKeys.provider('gone')), isFalse);
      expect(await service.contains(CredentialKeys.provider('alive')), isTrue);
    });
  });

  group('BackupFileScanner', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('bk_'));
    tearDown(() => tmp.delete(recursive: true));

    test('明文 v1 备份 → warn；v2 信封不报', () async {
      final plain = File('${tmp.path}/a.json')
        ..writeAsStringSync('{"provider_configs_v1":{"openai":{"apiKey":"sk-plain"}}}');
      final envelope = File('${tmp.path}/b.json')
        ..writeAsStringSync('{"format":"minime-core-backup","version":2,"crypto":null,"payload":{}}');

      final scanner = BackupFileScanner(Future.value([plain, envelope]));
      final findings = await scanner.scan(_FakeStrings());
      expect(findings.length, 1);
      expect(findings.first.severity, CheckupSeverity.warn);
      expect(findings.first.autoFixable, isFalse);
    });

    test('旧格式名 kelivo-backup 的 v2 信封也识别为安全（导入兼容）', () async {
      final legacy = File('${tmp.path}/legacy.json')
        ..writeAsStringSync('{"format":"kelivo-backup","version":2,"crypto":null,"payload":{}}');
      final scanner = BackupFileScanner(Future.value([legacy]));
      expect(await scanner.scan(_FakeStrings()), isEmpty);
    });

    test('文件不存在 / 损坏 → 安全跳过', () async {
      final scanner = BackupFileScanner(Future.value([File('${tmp.path}/nope.json')]));
      expect(await scanner.scan(_FakeStrings()), isEmpty);
    });
  });

  group('LogFileScanner', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('log_'));
    tearDown(() => tmp.delete(recursive: true));

    test('日志含明文 Key → warn', () async {
      // 前缀与主体分开拼接：避免 GitHub secret scanning 把仿真样本当真实密钥拦截。
      final sample = '${'sk' '-'}abcdefghijklmnopqrstuvw';
      final f = File('${tmp.path}/app.log')
        ..writeAsStringSync('normal line\nsomething $sample end\nother');
      final scanner = LogFileScanner(Future.value([f]));
      final findings = await scanner.scan(_FakeStrings());
      expect(findings.length, 1);
      expect(findings.first.severity, CheckupSeverity.warn);
      expect(findings.first.autoFixable, isFalse);
    });
  });
}

class _FakeStrings implements CheckupStrings {
  // 断言只依赖 id/severity 流转，文案值任意。
  @override
  String scannerErrorTitle(String scannerTitle) => 'err:$scannerTitle';
  @override
  String scannerErrorDetail() => 'd';
  @override
  String backupPlaintextTitle(int count) => 't:$count';
  @override
  String backupPlaintextDetail(List<String> files) => 'd:${files.length}';
  @override
  String legacyKeysTitle() => 't';
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

class _FakeScanner extends CheckupScanner {
  _FakeScanner(this.id, this._findings, {this.throwsOnScan = false});
  @override
  final String id;
  final List<CheckupFinding> _findings;
  final bool throwsOnScan;

  @override
  String get title => id;
  @override
  CheckupSeverity get severity => CheckupSeverity.warn;
  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async {
    if (throwsOnScan) throw StateError('boom');
    return _findings;
  }
}

class _FixableScanner extends CheckupScanner {
  _FixableScanner();
  bool fixed = false;
  @override
  String get id => 'fixable';
  @override
  String get title => 'fixable';
  @override
  CheckupSeverity get severity => CheckupSeverity.warn;
  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async => [
        CheckupFinding(
          id: '$id:a',
          scannerId: id,
          title: 't',
          detail: 'd',
          severity: CheckupSeverity.warn,
          autoFixable: true,
        )
      ];
  @override
  Future<bool> autoFix(CheckupFinding finding) async {
    fixed = true;
    return true;
  }
}
