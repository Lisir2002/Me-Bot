import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/models/service_credentials.dart';
import 'package:minime_core/core/services/migration/migration_context.dart';
import 'package:minime_core/core/services/migration/migration_runner.dart';
import 'package:minime_core/core/services/migration/steps/credential_migration_v1_step.dart';
import 'package:minime_core/core/services/migration/steps/credential_migration_v2_step.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';

import '../../../helpers/fake_secure_backend.dart';

const _searchKey = 'sk-search-legacy';
const _ttsKey = 'sk-tts-legacy';
const _searxPass = 'searx-pass';

Map<String, Object> dirtyPrefs() => <String, Object>{
      CredentialKeys.legacySearchServices: jsonEncode(<dynamic>[
        <String, dynamic>{'id': 's1', 'type': 'tavily', 'apiKey': _searchKey},
        <String, dynamic>{
          'id': 's2',
          'type': 'searxng',
          'url': 'https://searx.example.com',
          'username': 'u',
          'password': _searxPass,
        },
        <String, dynamic>{'id': 's3', 'type': 'bing_local'}, // 无凭证
      ]),
      CredentialKeys.legacyTtsServices: jsonEncode(<dynamic>[
        <String, dynamic>{'id': 't1', 'kind': 'openai', 'apiKey': _ttsKey},
      ]),
    };

Future<MigrationContext> buildContext(FakeBackend backend) async {
  SharedPreferences.setMockInitialValues(dirtyPrefs());
  final prefs = await SharedPreferences.getInstance();
  return MigrationContext(prefs: prefs, secureStorage: buildService(backend));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialMigrationV2Step', () {
    test('搜索 / TTS 的明文 Key 搬进安全存储', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV2Step().run(ctx);

      final s1 =
          await buildService(backend).readCredential(CredentialKeys.service('s1'));
      expect(ServiceCredentials.fromRecord(s1)['apiKey'], _searchKey);

      final t1 =
          await buildService(backend).readCredential(CredentialKeys.service('t1'));
      expect(ServiceCredentials.fromRecord(t1)['apiKey'], _ttsKey);
    });

    test('非 apiKey 凭证（searxng 口令）同样被搬走', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV2Step().run(ctx);

      final s2 =
          await buildService(backend).readCredential(CredentialKeys.service('s2'));
      final secrets = ServiceCredentials.fromRecord(s2);
      expect(secrets['password'], _searxPass);
      expect(secrets['username'], 'u');
    });

    test('prefs 重写后不含明文，但保留非敏感字段', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV2Step().run(ctx);

      final raw = ctx.prefs.getString(CredentialKeys.legacySearchServices)!;
      expect(raw.contains(_searchKey), isFalse);
      expect(raw.contains(_searxPass), isFalse);

      final list = jsonDecode(raw) as List;
      expect(list.length, 3);
      final s2 = list[1] as Map<String, dynamic>;
      expect(s2['url'], 'https://searx.example.com');
      expect(s2.containsKey('password'), isFalse);
      expect(s2.containsKey('username'), isFalse);
      // 无凭证的服务不受影响
      expect((list[2] as Map)['type'], 'bing_local');
    });

    test('重复执行幂等', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final step = CredentialMigrationV2Step();
      await step.run(ctx);
      final first = ctx.prefs.getString(CredentialKeys.legacySearchServices);
      await step.run(ctx);
      expect(ctx.prefs.getString(CredentialKeys.legacySearchServices), first);
    });

    test('本地已有值优先，不被旧明文覆盖', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final svc = buildService(backend);
      await svc.writeCredential(
        CredentialKeys.service('s1'),
        ServiceCredentials.toRecord('s1', <String, String>{'apiKey': 'newer'}),
      );

      await CredentialMigrationV2Step().run(ctx);

      final rec = await svc.readCredential(CredentialKeys.service('s1'));
      expect(ServiceCredentials.fromRecord(rec)['apiKey'], 'newer');
    });

    test('空 prefs 下安全空跑', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final backend = FakeBackend();
      final ctx = MigrationContext(
        prefs: prefs,
        secureStorage: buildService(backend),
      );
      await CredentialMigrationV2Step().run(ctx);
      expect(backend.store, isEmpty);
    });

    test('损坏 JSON 不抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CredentialKeys.legacySearchServices: '{not-json',
        CredentialKeys.legacyTtsServices: '{}',
      });
      final prefs = await SharedPreferences.getInstance();
      final ctx = MigrationContext(
        prefs: prefs,
        secureStorage: buildService(FakeBackend()),
      );
      await expectLater(CredentialMigrationV2Step().run(ctx), completes);
    });
  });

  group('v1 + v2 协同', () {
    test('注册表按版本顺序跑完两步', () async {
      final backend = FakeBackend();
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...dirtyPrefs(),
        CredentialKeys.legacyGlobalProxyPassword: 'gpass',
      });
      final prefs = await SharedPreferences.getInstance();
      final ctx = MigrationContext(
        prefs: prefs,
        secureStorage: buildService(backend),
      );

      final runner = MigrationRunner()
        ..register(CredentialMigrationV2Step())
        ..register(CredentialMigrationV1Step());

      final report = await runner.run(ctx);
      expect(report.ok, isTrue);
      expect(report.applied, 2);
      // v1 的清理生效：明文代理口令已删
      expect(
        ctx.prefs.getString(CredentialKeys.legacyGlobalProxyPassword),
        isNull,
      );
      // v2 的凭证已入库
      expect(
        await buildService(backend).read(CredentialKeys.globalProxyPassword),
        'gpass',
      );
    });
  });
}
