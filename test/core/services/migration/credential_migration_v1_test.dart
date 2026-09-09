import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/models/provider_credentials.dart';
import 'package:minime_core/core/services/migration/migration_context.dart';
import 'package:minime_core/core/services/migration/migration_runner.dart';
import 'package:minime_core/core/services/migration/migration_step.dart';
import 'package:minime_core/core/services/migration/steps/credential_migration_v1_step.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';

import '../../../helpers/fake_secure_backend.dart';

const _secret = 'sk-legacy-plaintext-key';
const _multi = 'sk-multi-legacy';
const _proxyPass = 'proxy-secret';
const _webdavPass = 'webdav-secret';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 构造一份「迁移前」的脏 SharedPreferences：凭证全在明文里。
  Map<String, Object> dirtyPrefs() => <String, Object>{
        CredentialKeys.legacyProviderConfigs: jsonEncode(<String, dynamic>{
          'OpenAI': <String, dynamic>{
            'id': 'OpenAI',
            'enabled': true,
            'name': 'OpenAI',
            'apiKey': _secret,
            'baseUrl': 'https://api.openai.com/v1',
            'proxyUsername': 'bob',
            'proxyPassword': _proxyPass,
            'multiKeyEnabled': true,
            'apiKeys': <dynamic>[
              <String, dynamic>{'id': 'k1', 'key': _multi, 'priority': 2},
            ],
          },
          'Empty': <String, dynamic>{'id': 'Empty', 'apiKey': ''},
        }),
        CredentialKeys.legacyGlobalProxyUsername: 'guser',
        CredentialKeys.legacyGlobalProxyPassword: 'gpass',
        CredentialKeys.legacyWebDavConfig: jsonEncode(<String, dynamic>{
          'url': 'https://dav.example.com',
          'username': 'davuser',
          'password': _webdavPass,
        }),
      };

  Future<MigrationContext> buildContext(
    FakeBackend backend, {
    List<String>? logSink,
  }) async {
    SharedPreferences.setMockInitialValues(dirtyPrefs());
    final prefs = await SharedPreferences.getInstance();
    return MigrationContext(
      prefs: prefs,
      secureStorage: buildService(backend),
      log: (level, message, [error, stack]) => logSink?.add('$level:$message'),
    );
  }

  group('CredentialMigrationV1Step', () {
    test('明文凭证搬进安全存储', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV1Step().run(ctx);

      final record = await buildService(backend)
          .readCredential(CredentialKeys.provider('OpenAI'));
      final creds = ProviderCredentials.fromRecord(record);
      expect(creds.apiKey, _secret);
      expect(creds.proxyUsername, 'bob');
      expect(creds.proxyPassword, _proxyPass);
      expect(creds.apiKeys['k1'], _multi);

      expect(
        await buildService(backend).read(CredentialKeys.globalProxyUsername),
        'guser',
      );
      expect(
        await buildService(backend).read(CredentialKeys.globalProxyPassword),
        'gpass',
      );
      expect(
        await buildService(backend).read(CredentialKeys.webDavPassword),
        _webdavPass,
      );
    });

    test('旧明文 key 被立即删除（拍板①）', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV1Step().run(ctx);

      final prefs = ctx.prefs;
      expect(
          prefs.containsKey(CredentialKeys.legacyGlobalProxyUsername), isFalse);
      expect(
          prefs.containsKey(CredentialKeys.legacyGlobalProxyPassword), isFalse);
    });

    test('provider_configs 重写后不含明文，但保留非敏感配置', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV1Step().run(ctx);

      final raw = ctx.prefs.getString(CredentialKeys.legacyProviderConfigs)!;
      expect(raw.contains(_secret), isFalse);
      expect(raw.contains(_multi), isFalse);
      expect(raw.contains(_proxyPass), isFalse);

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final openai = decoded['OpenAI'] as Map<String, dynamic>;
      expect(openai['baseUrl'], 'https://api.openai.com/v1');
      expect(openai['enabled'], true);
      // 多 Key 元数据保留
      expect((openai['apiKeys'] as List).length, 1);
    });

    test('webdav 配置保留非敏感字段、剥掉 password', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      await CredentialMigrationV1Step().run(ctx);

      final raw = ctx.prefs.getString(CredentialKeys.legacyWebDavConfig)!;
      expect(raw.contains(_webdavPass), isFalse);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['url'], 'https://dav.example.com');
      expect(decoded['username'], 'davuser');
      expect(decoded.containsKey('password'), isFalse);
    });

    test('重复执行幂等：凭证不丢、不重复写坏', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);

      final step = CredentialMigrationV1Step();
      await step.run(ctx);
      final firstRaw =
          ctx.prefs.getString(CredentialKeys.legacyProviderConfigs);

      await step.run(ctx);
      final secondRaw =
          ctx.prefs.getString(CredentialKeys.legacyProviderConfigs);

      expect(secondRaw, firstRaw, reason: '第二次执行不应改变已迁移结果');
      final creds = ProviderCredentials.fromRecord(
        await buildService(backend)
            .readCredential(CredentialKeys.provider('OpenAI')),
      );
      expect(creds.apiKey, _secret);
    });

    test('安全存储已有新值时，不被旧明文覆盖', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final svc = buildService(backend);
      // 模拟「A 阶段已写入较新凭证，明文是过期数据」
      await svc.write(CredentialKeys.globalProxyPassword, 'newer-value');

      await CredentialMigrationV1Step().run(ctx);

      expect(
        await svc.read(CredentialKeys.globalProxyPassword),
        'newer-value',
      );
    });

    test('写入失败时整步失败，明文保留（fail-open 数据安全）', () async {
      // failOnWrite：A 阶段抛错 → B 阶段不会执行 → 明文仍在
      final backend = FakeBackend(failOnWrite: true);
      final ctx = await buildContext(backend);

      await expectLater(
        CredentialMigrationV1Step().run(ctx),
        throwsA(isA<Object>()),
      );
      // 明文未被删除，下次启动可重试
      expect(
        ctx.prefs.getString(CredentialKeys.legacyGlobalProxyPassword),
        'gpass',
      );
    });

    test('空 preferences 下安全空跑：不写凭证，只落审计锚点', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final backend = FakeBackend();
      final ctx = MigrationContext(
        prefs: prefs,
        secureStorage: buildService(backend),
      );

      await CredentialMigrationV1Step().run(ctx);
      // 没有 legacy 明文 → 不得写入任何凭证；
      // 唯一允许落盘的是「迁移已跑过」审计锚点，PR-5 安全体检用它判断设备状态。
      expect(backend.store.keys, <String>{CredentialKeys.migrationV1Done});
    });

    test('损坏的 JSON 不抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CredentialKeys.legacyProviderConfigs: '{not-json',
        CredentialKeys.legacyWebDavConfig: '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final backend = FakeBackend();
      final ctx = MigrationContext(
        prefs: prefs,
        secureStorage: buildService(backend),
      );

      await expectLater(
        CredentialMigrationV1Step().run(ctx),
        completes,
      );
    });

    test('明文回流（旧备份恢复）会被清理，但不覆盖安全存储已有值', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final step = CredentialMigrationV1Step();
      final runner = MigrationRunner()..register(step);

      await runner.run(ctx);
      expect(ctx.isDone('credential_v1'), isTrue);

      // 模拟用户从旧备份恢复：明文凭证又被整体写回 SharedPreferences
      await ctx.prefs
          .setString(CredentialKeys.legacyGlobalProxyPassword, 'gpass');
      await ctx.prefs.setString(
        CredentialKeys.legacyProviderConfigs,
        jsonEncode(<String, dynamic>{
          'OpenAI': <String, dynamic>{'id': 'OpenAI', 'apiKey': 'sk-restored'},
        }),
      );

      await runner.run(ctx);

      // 明文被清掉（安全核心），但安全存储保留的是**先迁移进去**的值
      // —— 迁移层遵循「本地优先」语义，不拿恢复来的明文覆盖已有凭证。
      // 「恢复的备份凭证应该生效」由恢复路径负责：BackupCredentialBridge
      // .absorbOnRestore 在 prefs 恢复前就把备份凭证写进安全存储（备份优先），
      // 迁移层只兜底清理明文，两条路各管一段，不抢语义。
      expect(
        ctx.prefs.getString(CredentialKeys.legacyGlobalProxyPassword),
        isNull,
      );
      final raw = ctx.prefs.getString(CredentialKeys.legacyProviderConfigs)!;
      expect(raw.contains('sk-restored'), isFalse);
      final creds = ProviderCredentials.fromRecord(
        await buildService(backend)
            .readCredential(CredentialKeys.provider('OpenAI')),
      );
      expect(creds.apiKey, 'sk-legacy-plaintext-key');
    });
  });

  group('MigrationRunner', () {
    test('按版本号升序执行', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final order = <int>[];

      final runner = MigrationRunner()
        ..register(_RecordingStep(2, order))
        ..register(_RecordingStep(1, order))
        ..register(_RecordingStep(3, order));

      final report = await runner.run(ctx);
      expect(order, <int>[1, 2, 3]);
      expect(report.applied, 3);
      expect(report.ok, isTrue);
    });

    test('已完成的步骤被跳过', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final order = <int>[];
      final step = _RecordingStep(1, order);

      final runner = MigrationRunner()..register(step);
      await runner.run(ctx);
      await runner.run(ctx); // 第二次：shouldRun 返回 false

      expect(order, <int>[1], reason: '第二次运行应整体跳过');
      expect(step.runCount, 1);
    });

    test('单步失败不阻断后续步骤（fail-open）', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final order = <int>[];

      final runner = MigrationRunner()
        ..register(_RecordingStep(1, order))
        ..register(_ThrowingStep(2))
        ..register(_RecordingStep(3, order));

      final report = await runner.run(ctx);
      expect(order, <int>[1, 3]);
      expect(report.failed, 1);
      expect(report.ok, isFalse);
    });

    test('重复 id 只保留先注册者', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final order = <int>[];

      final runner = MigrationRunner()
        ..register(_RecordingStep(1, order, id: 'same'))
        ..register(_RecordingStep(1, order, id: 'same'));

      await runner.run(ctx);
      expect(order, <int>[1]);
    });

    test('真实装配：跑完 credential_v1 后标记完成', () async {
      final backend = FakeBackend();
      final ctx = await buildContext(backend);
      final runner = MigrationRunner()..register(CredentialMigrationV1Step());

      final report = await runner.run(ctx);
      expect(report.ok, isTrue);
      expect(report.applied, 1);
      expect(ctx.isDone('credential_v1'), isTrue);
    });
  });
}

class _RecordingStep extends MigrationStep {
  _RecordingStep(this.version, this.order, {String? id})
      : _id = id ?? 'v$version';

  final List<int> order;
  final String _id;
  int runCount = 0;

  @override
  String get id => _id;

  @override
  final int version;

  @override
  Future<void> run(MigrationContext ctx) async {
    runCount++;
    order.add(version);
  }
}

class _ThrowingStep extends MigrationStep {
  _ThrowingStep(this.version);

  @override
  String get id => 'boom$version';

  @override
  final int version;

  @override
  Future<void> run(MigrationContext ctx) async => throw StateError('nope');
}
