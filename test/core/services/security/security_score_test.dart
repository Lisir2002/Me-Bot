import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/security/checkup_scanner.dart';
import 'package:minime_core/core/services/security/key_health_service.dart';
import 'package:minime_core/features/security/widgets/security_score_card.dart';

void main() {
  group('SecurityScoreLevel', () {
    test('分数区间映射正确', () {
      expect(SecurityScoreLevel.fromScore(100), SecurityScoreLevel.excellent);
      expect(SecurityScoreLevel.fromScore(90), SecurityScoreLevel.excellent);
      expect(SecurityScoreLevel.fromScore(89), SecurityScoreLevel.good);
      expect(SecurityScoreLevel.fromScore(70), SecurityScoreLevel.good);
      expect(SecurityScoreLevel.fromScore(69), SecurityScoreLevel.fair);
      expect(SecurityScoreLevel.fromScore(50), SecurityScoreLevel.fair);
      expect(SecurityScoreLevel.fromScore(49), SecurityScoreLevel.danger);
      expect(SecurityScoreLevel.fromScore(0), SecurityScoreLevel.danger);
    });
  });

  group('SecurityScoreResult.compute', () {
    test('无任何问题 + 门禁白名单全开 → 120 分 clamp 到 100', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(findings: const [], scannedAt: DateTime.now()),
        health: const [],
        lockEnabled: true,
        allowlistEnabled: true,
      );
      expect(r.score, 100);
      expect(r.level, SecurityScoreLevel.excellent);
    });

    test('基础分 100，无任何加分项 → 100', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(findings: const [], scannedAt: DateTime.now()),
        health: const [],
      );
      expect(r.score, 100);
    });

    test('1 个 danger → 扣 20 → 80 分', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(
          findings: [
            CheckupFinding(
              id: 'd1',
              scannerId: 's',
              title: 't',
              detail: 'd',
              severity: CheckupSeverity.danger,
            ),
          ],
          scannedAt: DateTime.now(),
        ),
      );
      expect(r.score, 80);
      expect(r.dangerCount, 1);
      expect(r.level, SecurityScoreLevel.good);
    });

    test('1 个 warn → 扣 10 → 90 分', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(
          findings: [
            CheckupFinding(
              id: 'w1',
              scannerId: 's',
              title: 't',
              detail: 'd',
              severity: CheckupSeverity.warn,
            ),
          ],
          scannedAt: DateTime.now(),
        ),
      );
      expect(r.score, 90);
      expect(r.warnCount, 1);
    });

    test('1 个需轮换密钥 → 扣 15 → 85 分', () {
      final r = SecurityScoreResult.compute(
        health: [
          const KeyHealthInfo(providerId: 'p', keyCount: 1, needsRotation: true),
        ],
      );
      expect(r.score, 85);
      expect(r.rotationCount, 1);
    });

    test('门禁开启 +10，白名单开启 +10', () {
      final r = SecurityScoreResult.compute(
        lockEnabled: true,
        allowlistEnabled: true,
      );
      expect(r.score, 100); // 100 + 10 + 10 = 120 → clamp 100
      expect(r.lockEnabled, isTrue);
      expect(r.allowlistEnabled, isTrue);
    });

    test('综合扣分：2 danger + 1 warn + 1 轮换 → 35 分（危险）', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(
          findings: [
            for (var i = 0; i < 2; i++)
              CheckupFinding(
                id: 'd$i',
                scannerId: 's',
                title: 't',
                detail: 'd',
                severity: CheckupSeverity.danger,
              ),
            CheckupFinding(
              id: 'w1',
              scannerId: 's',
              title: 't',
              detail: 'd',
              severity: CheckupSeverity.warn,
            ),
          ],
          scannedAt: DateTime.now(),
        ),
        health: [
          const KeyHealthInfo(providerId: 'p', keyCount: 1, needsRotation: true),
        ],
      );
      // 100 - 40 - 10 - 15 = 35
      expect(r.score, 35);
      expect(r.level, SecurityScoreLevel.danger);
    });

    test('分数不会低于 0', () {
      final r = SecurityScoreResult.compute(
        report: CheckupReport(
          findings: [
            for (var i = 0; i < 10; i++)
              CheckupFinding(
                id: 'd$i',
                scannerId: 's',
                title: 't',
                detail: 'd',
                severity: CheckupSeverity.danger,
              ),
          ],
          scannedAt: DateTime.now(),
        ),
      );
      expect(r.score, 0); // 100 - 200 = -100 → clamp 0
    });

    test('report 为 null 时不扣分', () {
      final r = SecurityScoreResult.compute(report: null);
      expect(r.score, 100);
      expect(r.dangerCount, 0);
      expect(r.warnCount, 0);
    });
  });
}
