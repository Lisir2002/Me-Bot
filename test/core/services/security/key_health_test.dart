import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/models/provider_credentials.dart';
import 'package:minime_core/core/services/security/key_health_service.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';
import 'package:minime_core/core/services/secure_storage/credential_record.dart';

import '../../../helpers/fake_secure_backend.dart';

void main() {
  group('KeyHealthService', () {
    test('扫描 provider 凭证，聚合健康快照', () async {
      final svc = buildService(FakeBackend());
      final creds = ProviderCredentials(
        apiKey: 'sk-main',
        apiKeys: {'k1': 'x', 'k2': 'y'},
        serviceAccountJson: '{"project_id":"acme"}',
      );
      await svc.writeCredential(
        CredentialKeys.provider('openai'),
        creds.toRecord('openai').markRotated(),
      );

      final infos = await KeyHealthService(svc).scan();
      expect(infos.length, 1);
      final info = infos.first;
      expect(info.providerId, 'openai');
      expect(info.keyCount, 4); // apiKey + 2 apiKeys + serviceAccount
      expect(info.hasServiceAccount, isTrue);
      expect(info.lastRotatedAt, isNotNull);
      expect(info.needsRotation, isFalse); // 刚 markRotated
      expect(info.daysSinceRotation, 0);
    });

    test('从未轮换 → needsRotation=true', () async {
      final svc = buildService(FakeBackend());
      final creds = ProviderCredentials(apiKey: 'sk-x');
      await svc.writeCredential(
        CredentialKeys.provider('g'),
        creds.toRecord('g'), // 不 markRotated
      );
      final infos = await KeyHealthService(svc).scan();
      expect(infos.first.needsRotation, isTrue);
      expect(infos.first.daysSinceRotation, isNull);
    });

    test('超过轮换阈值（默认 90 天）→ needsRotation=true', () async {
      final svc = buildService(FakeBackend());
      final record = CredentialRecord.create(type: CredentialType.apiKey, value: 'v')
        ..markRotated();
      // 把 lastRotatedAt 拨回 120 天前
      final old = record.copyWith(
        lastRotatedAt: DateTime.now().subtract(const Duration(days: 120)),
      );
      await svc.writeCredential(CredentialKeys.provider('old'), old);
      final infos = await KeyHealthService(svc).scan();
      expect(infos.first.needsRotation, isTrue);
      expect(infos.first.daysSinceRotation, greaterThanOrEqualTo(120));
    });

    test('自定义阈值生效', () async {
      final svc = buildService(FakeBackend());
      final record = CredentialRecord.create(type: CredentialType.apiKey, value: 'v')
        ..markRotated();
      final old = record.copyWith(
        lastRotatedAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      await svc.writeCredential(CredentialKeys.provider('p'), old);
      // 阈值 5 天 → 已超
      final infos = await KeyHealthService(svc, rotationThresholdDays: 5).scan();
      expect(infos.first.needsRotation, isTrue);
      // 阈值 30 天 → 未超
      final infos2 = await KeyHealthService(svc, rotationThresholdDays: 30).scan();
      expect(infos2.first.needsRotation, isFalse);
    });

    test('service 凭证（非 provider）不计入密钥健康', () async {
      final svc = buildService(FakeBackend());
      await svc.writeCredential(
        CredentialKeys.service('search1'),
        ProviderCredentials(apiKey: 'sk-s').toRecord('search1'),
      );
      expect(await KeyHealthService(svc).scan(), isEmpty);
    });

    test('markRotated 更新轮换时间 → needsRotation 翻转为 false', () async {
      final svc = buildService(FakeBackend());
      await svc.writeCredential(
        CredentialKeys.provider('stale'),
        ProviderCredentials(apiKey: 'sk-x').toRecord('stale'), // 从未轮换
      );
      final health = KeyHealthService(svc);
      expect((await health.scan()).first.needsRotation, isTrue);

      expect(await health.markRotated('stale'), isTrue);
      final after = await health.scan();
      expect(after.first.needsRotation, isFalse);
      expect(after.first.daysSinceRotation, 0);
      expect(after.first.lastRotatedAt, isNotNull);
    });

    test('markRotated：provider 不存在 → 返回 false 且不抛异常', () async {
      final svc = buildService(FakeBackend());
      expect(await KeyHealthService(svc).markRotated('ghost'), isFalse);
    });
  });

  group('KeyHealthInfo 倒计时计算', () {
    const threshold = 90;

    test('从未轮换 → daysUntilRotation=null, isOverdue=true, daysOverdue=null', () {
      final info = KeyHealthInfo(providerId: 'p', keyCount: 1);
      expect(info.daysUntilRotation(threshold), isNull);
      expect(info.isOverdue(threshold), isTrue);
      expect(info.daysOverdue(threshold), isNull);
    });

    test('刚轮换 → daysUntilRotation≈90, isOverdue=false, daysOverdue=0', () {
      final info = KeyHealthInfo(
        providerId: 'p',
        keyCount: 1,
        lastRotatedAt: DateTime.now(),
      );
      expect(info.daysUntilRotation(threshold), greaterThanOrEqualTo(89));
      expect(info.isOverdue(threshold), isFalse);
      expect(info.daysOverdue(threshold), 0);
    });

    test('轮换 80 天前 → 未超期，距到期约 10 天', () {
      final info = KeyHealthInfo(
        providerId: 'p',
        keyCount: 1,
        lastRotatedAt: DateTime.now().subtract(const Duration(days: 80)),
      );
      expect(info.daysUntilRotation(threshold), lessThanOrEqualTo(10));
      expect(info.daysUntilRotation(threshold), greaterThanOrEqualTo(9));
      expect(info.isOverdue(threshold), isFalse);
      expect(info.daysOverdue(threshold), 0);
    });

    test('轮换 100 天前 → 已超期约 10 天', () {
      final info = KeyHealthInfo(
        providerId: 'p',
        keyCount: 1,
        lastRotatedAt: DateTime.now().subtract(const Duration(days: 100)),
      );
      expect(info.daysUntilRotation(threshold), lessThanOrEqualTo(-9));
      expect(info.isOverdue(threshold), isTrue);
      expect(info.daysOverdue(threshold), greaterThanOrEqualTo(9));
      expect(info.daysOverdue(threshold), lessThanOrEqualTo(11));
    });

    test('自定义阈值生效', () {
      final info = KeyHealthInfo(
        providerId: 'p',
        keyCount: 1,
        lastRotatedAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(info.isOverdue(5), isTrue); // 阈值 5 天 → 超期
      expect(info.isOverdue(30), isFalse); // 阈值 30 天 → 未超期
      expect(info.daysOverdue(5), greaterThanOrEqualTo(4));
    });
  });
}
