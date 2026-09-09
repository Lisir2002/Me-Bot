import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/credential_audit_logger.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CredentialAuditLogger.resetForTest();
    // 预热：完成首次 hydrate（读当前空 store），之后 record→recent 走纯内存，
    // 不与 fire-and-forget 写盘产生竞态。
    await CredentialAuditLogger.recent(limit: 0);
  });

  group('CredentialAuditLogger 结构化事件', () {
    test('record → recent 按新→旧返回', () async {
      CredentialAuditLogger.record('view', 'provider:openai');
      CredentialAuditLogger.record('copy', 'provider:openai', ok: false);
      final events = await CredentialAuditLogger.recent();
      expect(events.length, 2);
      expect(events.first.action, 'copy'); // 最新在前
      expect(events.first.ok, isFalse);
      expect(events.last.action, 'view');
      expect(events.last.ok, isTrue);
    });

    test('事件不含凭证明文：仅操作名/对象类别/结果', () async {
      CredentialAuditLogger.record('copy', 'provider:openai', detail: 'keys=3');
      final events = await CredentialAuditLogger.recent();
      expect(events.first.action, 'copy');
      expect(events.first.target, 'provider:openai');
      expect(events.first.detail, 'keys=3');
    });

    test('ring buffer 上限 maxEvents，最新保留', () async {
      for (var i = 0; i < CredentialAuditLogger.maxEvents + 10; i++) {
        CredentialAuditLogger.record('view', 'p:$i');
      }
      // recent 默认 limit=20，这里显式放大以验证 ring buffer 本身的容量。
      final events = await CredentialAuditLogger.recent(
          limit: CredentialAuditLogger.maxEvents + 5);
      expect(events.length, CredentialAuditLogger.maxEvents);
      expect(events.first.target,
          'p:${CredentialAuditLogger.maxEvents + 9}');
    });

    test('limit 参数生效', () async {
      for (var i = 0; i < 15; i++) {
        CredentialAuditLogger.record('view', 'p:$i');
      }
      final events = await CredentialAuditLogger.recent(limit: 5);
      expect(events.length, 5);
      expect(events.first.target, 'p:14');
    });

    test('持久化往返：重置内存后 recent 从 prefs 恢复', () async {
      CredentialAuditLogger.record('export', 'backup:encrypted');
      await pumpEventQueue(); // 等待 fire-and-forget 写盘
      CredentialAuditLogger.resetForTest();
      final events = await CredentialAuditLogger.recent();
      expect(events, isNotEmpty);
      expect(events.first.action, 'export');
      expect(events.first.target, 'backup:encrypted');
    });

    test('clear 清空全部并留下一条 clearAudit', () async {
      CredentialAuditLogger.record('view', 'p1');
      await CredentialAuditLogger.clear();
      final events = await CredentialAuditLogger.recent();
      expect(events.length, 1);
      expect(events.first.action, 'clearAudit');
    });

    test('损坏的持久化数据被安全跳过', () async {
      SharedPreferences.setMockInitialValues({
        'audit_events': [
          '{bad json',
          jsonEncode({'t': '2026-01-01T08:00:00', 'a': 'view', 'g': 'p', 'ok': '1'}),
        ],
      });
      // 注入了新 store 后需重置 hydrate 状态，强制从新 store 恢复。
      CredentialAuditLogger.resetForTest();
      final events = await CredentialAuditLogger.recent();
      expect(events.length, 1);
      expect(events.first.action, 'view');
      expect(events.first.time, DateTime(2026, 1, 1, 8));
    });

    test('ok=false 事件标记失败', () async {
      CredentialAuditLogger.record('enterPassphrase', 'backup:encrypted',
          ok: false);
      final events = await CredentialAuditLogger.recent();
      expect(events.first.ok, isFalse);
    });
  });
}
