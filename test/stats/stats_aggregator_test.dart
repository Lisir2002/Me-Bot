import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/core/models/assistant.dart';
import 'package:minime_core/core/models/chat_message.dart';
import 'package:minime_core/core/models/conversation.dart';
import 'package:minime_core/core/services/stats/stats_aggregator.dart';

// ─────────────────────────────────────────────────────────────
// 测试数据构造辅助
// ─────────────────────────────────────────────────────────────

/// 构造一条测试消息。token 相关字段按需传入。
ChatMessage _msg({
  required String id,
  required String conversationId,
  required DateTime timestamp,
  String? modelId,
  int? totalTokens,
  int? promptTokens,
  int? completionTokens,
  int? cachedTokens,
}) {
  return ChatMessage(
    id: id,
    role: 'assistant',
    content: 'content-$id',
    timestamp: timestamp,
    modelId: modelId,
    totalTokens: totalTokens,
    conversationId: conversationId,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    cachedTokens: cachedTokens,
  );
}

/// 构造一个测试会话。
Conversation _convo({
  required String id,
  required DateTime createdAt,
  String? assistantId,
  String title = '',
  List<String> messageIds = const [],
}) {
  return Conversation(
    id: id,
    title: title,
    createdAt: createdAt,
    assistantId: assistantId,
    messageIds: messageIds,
  );
}

/// 构造一个测试助手。
Assistant _assistant({required String id, required String name}) {
  return Assistant(id: id, name: name);
}

void main() {
  // 固定“当前时间”，避免 DateTime.now() 抖动。
  final now = DateTime(2026, 9, 15);

  // 空会话/助手列表的便捷参数。
  const emptyConvos = <Conversation>[];
  const emptyAssistants = <Assistant>[];

  group('1. 时间窗口过滤', () {
    test('lastMonth 不包含本月数据', () {
      final messages = [
        _msg(
          id: 'm1',
          conversationId: 'c1',
          timestamp: DateTime(2026, 8, 20), // 上月，应计入
        ),
        _msg(
          id: 'm2',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 5), // 本月，不应计入
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.lastMonth,
        now: now,
      );
      expect(s.messageCount, 1);
      // lastMonth 窗口应为 [2026-08-01, 2026-08-31]
      expect(s.window.start, DateTime(2026, 8, 1));
      expect(s.window.end, DateTime(2026, 8, 31));
    });

    test('last30 包含最近 30 天（2026-08-17 ~ 2026-09-15）', () {
      final messages = [
        _msg(
          id: 'in-start',
          conversationId: 'c1',
          timestamp: DateTime(2026, 8, 17), // 窗口起点，应计入
        ),
        _msg(
          id: 'in-end',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 15), // 窗口终点，应计入
        ),
        _msg(
          id: 'out',
          conversationId: 'c1',
          timestamp: DateTime(2026, 8, 16), // 窗口外，不应计入
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.last30,
        now: now,
      );
      expect(s.messageCount, 2);
      expect(s.window.start, DateTime(2026, 8, 17));
      expect(s.window.end, DateTime(2026, 9, 15));
    });

    test('all 包含所有消息', () {
      final messages = [
        _msg(id: 'm1', conversationId: 'c1', timestamp: DateTime(2025, 1, 1)),
        _msg(id: 'm2', conversationId: 'c1', timestamp: DateTime(2026, 9, 15)),
        _msg(id: 'm3', conversationId: 'c1', timestamp: DateTime(2026, 9, 14)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.messageCount, 3);
      expect(s.window.start, isNull);
      expect(s.window.end, isNull);
    });

    test('lastQuarter 包含最近 3 个自然月（不含当月）', () {
      // now=2026-09-15 → 窗口 [2026-06-01, 2026-08-31]
      final messages = [
        _msg(id: 'jun', conversationId: 'c1', timestamp: DateTime(2026, 6, 15)),
        _msg(id: 'jul', conversationId: 'c1', timestamp: DateTime(2026, 7, 15)),
        _msg(id: 'aug', conversationId: 'c1', timestamp: DateTime(2026, 8, 15)),
        _msg(id: 'may-out', conversationId: 'c1', timestamp: DateTime(2026, 5, 15)),
        _msg(id: 'sep-out', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.lastQuarter,
        now: now,
      );
      expect(s.messageCount, 3);
      expect(s.window.start, DateTime(2026, 6, 1));
      expect(s.window.end, DateTime(2026, 8, 31));
    });
  });

  group('2. conversationCount 按消息去重', () {
    test('2 个会话各有多条消息 → conversationCount == 2', () {
      final messages = [
        _msg(id: 'm1', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
        _msg(id: 'm2', conversationId: 'c1', timestamp: DateTime(2026, 9, 2)),
        _msg(id: 'm3', conversationId: 'c1', timestamp: DateTime(2026, 9, 3)),
        _msg(id: 'm4', conversationId: 'c2', timestamp: DateTime(2026, 9, 4)),
        _msg(id: 'm5', conversationId: 'c2', timestamp: DateTime(2026, 9, 5)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.conversationCount, 2);
      expect(s.messageCount, 5);
    });

    test('另一会话在窗口内无消息 → 不计入', () {
      final conversations = [
        _convo(id: 'c1', createdAt: DateTime(2026, 9, 1)),
        _convo(id: 'c2', createdAt: DateTime(2026, 9, 2)), // 窗口内创建但无消息
      ];
      final messages = [
        _msg(id: 'm1', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
        _msg(id: 'm2', conversationId: 'c1', timestamp: DateTime(2026, 9, 2)),
      ];
      final s = StatsSnapshot.compute(
        conversations: conversations,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.conversationCount, 1);
    });
  });

  group('3. token 聚合', () {
    test('老消息只有 totalTokens → 计入 totalTokens', () {
      final messages = [
        _msg(
          id: 'm1',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 1),
          modelId: 'model-x',
          totalTokens: 100,
          promptTokens: null,
          completionTokens: null,
          cachedTokens: null,
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.modelRows.single.token, 100);
      // 老消息无分项，分项汇总应为 0
      expect(s.promptTokens, 0);
      expect(s.completionTokens, 0);
      expect(s.cachedTokens, 0);
    });

    test('新消息有分项 → 计入 prompt+completion', () {
      final messages = [
        _msg(
          id: 'm1',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 1),
          modelId: 'model-x',
          totalTokens: null,
          promptTokens: 30,
          completionTokens: 70,
          cachedTokens: 10,
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.modelRows.single.token, 100); // 30 + 70
      expect(s.promptTokens, 30);
      expect(s.completionTokens, 70);
      expect(s.cachedTokens, 10);
    });

    test('totalTokens 优先于分项（不叠加成 200）', () {
      final messages = [
        _msg(
          id: 'm1',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 1),
          modelId: 'model-x',
          totalTokens: 100,
          promptTokens: 30,
          completionTokens: 70,
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      // 计费 token 取 totalTokens，而非 30+70=100 再与 100 叠加
      expect(s.modelRows.single.token, 100);
    });

    test('promptTokens / completionTokens / cachedTokens 汇总正确', () {
      final messages = [
        _msg(
          id: 'm1',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 1),
          promptTokens: 30,
          completionTokens: 70,
          cachedTokens: 5,
        ),
        _msg(
          id: 'm2',
          conversationId: 'c1',
          timestamp: DateTime(2026, 9, 2),
          promptTokens: 10,
          completionTokens: 20,
          cachedTokens: 3,
        ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.promptTokens, 40);
      expect(s.completionTokens, 90);
      expect(s.cachedTokens, 8);
    });
  });

  group('4. 模型排行按 token 排序', () {
    test('token 多的排第一，value 保留消息条数', () {
      final messages = [
        // 模型 A：2 条各 50 → 共 100
        _msg(
            id: 'a1',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 1),
            modelId: 'model-a',
            totalTokens: 50),
        _msg(
            id: 'a2',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 2),
            modelId: 'model-a',
            totalTokens: 50),
        // 模型 B：1 条 200 → 共 200
        _msg(
            id: 'b1',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 3),
            modelId: 'model-b',
            totalTokens: 200),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.modelRows.length, 2);
      expect(s.modelRows[0].name, 'model-b');
      expect(s.modelRows[0].token, 200);
      expect(s.modelRows[0].value, 1);
      expect(s.modelRows[1].name, 'model-a');
      expect(s.modelRows[1].token, 100);
      expect(s.modelRows[1].value, 2);
    });
  });

  group('5. 助手排行按 token 排序', () {
    test('助手 Y token 多排第一，助手 X 次之', () {
      final assistants = [
        _assistant(id: 'asst-x', name: '助手X'),
        _assistant(id: 'asst-y', name: '助手Y'),
      ];
      final conversations = [
        _convo(id: 'cx', createdAt: DateTime(2026, 9, 1), assistantId: 'asst-x'),
        _convo(id: 'cy', createdAt: DateTime(2026, 9, 1), assistantId: 'asst-y'),
      ];
      final messages = [
        // 助手 X：2 条各 50 → 100
        _msg(
            id: 'x1',
            conversationId: 'cx',
            timestamp: DateTime(2026, 9, 1),
            totalTokens: 50),
        _msg(
            id: 'x2',
            conversationId: 'cx',
            timestamp: DateTime(2026, 9, 2),
            totalTokens: 50),
        // 助手 Y：1 条 200 → 200
        _msg(
            id: 'y1',
            conversationId: 'cy',
            timestamp: DateTime(2026, 9, 3),
            totalTokens: 200),
      ];
      final s = StatsSnapshot.compute(
        conversations: conversations,
        messages: messages,
        assistants: assistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.assistantRows.length, 2);
      expect(s.assistantRows[0].name, '助手Y');
      expect(s.assistantRows[0].token, 200);
      expect(s.assistantRows[1].name, '助手X');
      expect(s.assistantRows[1].token, 100);
    });

    test('未绑定助手（assistantId == null）归到全局', () {
      final conversations = [
        // assistantId 为 null
        _convo(id: 'cg', createdAt: DateTime(2026, 9, 1), assistantId: null),
      ];
      final messages = [
        _msg(
            id: 'g1',
            conversationId: 'cg',
            timestamp: DateTime(2026, 9, 1),
            totalTokens: 100),
      ];
      final s = StatsSnapshot.compute(
        conversations: conversations,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.assistantRows.single.name, StatsSnapshot.globalAssistantKey);
      expect(s.assistantRows.single.token, 100);
    });
  });

  group('6. 趋势桶粒度', () {
    test('跨度 ≤31 天 → daily == true', () {
      final messages = [
        for (var i = 0; i < 10; i++)
          _msg(
            id: 'd$i',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 1 + i),
            modelId: 'model-x',
            totalTokens: 10,
          ),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.trend.daily, isTrue);
      expect(s.trend.isEmpty, isFalse);
    });

    test('跨度 >31 天 → daily == false（按月聚合）', () {
      final messages = [
        _msg(
            id: 'early',
            conversationId: 'c1',
            timestamp: DateTime(2026, 7, 1),
            modelId: 'model-x',
            totalTokens: 10),
        _msg(
            id: 'late',
            conversationId: 'c1',
            timestamp: DateTime(2026, 8, 30),
            modelId: 'model-x',
            totalTokens: 10),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.trend.daily, isFalse);
    });

    test('空消息 → trend.isEmpty == true', () {
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.trend.isEmpty, isTrue);
      expect(s.trend.buckets, isEmpty);
    });
  });

  group('7. launchCount 过滤', () {
    test('传入 launchDates → 按窗口过滤计数', () {
      // last30 窗口 [2026-08-17, 2026-09-15]
      final launchDates = [
        DateTime(2026, 9, 1), // 窗口内
        DateTime(2026, 9, 10), // 窗口内
        DateTime(2026, 8, 15), // 窗口外
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 999, // 传错原值也应被覆盖
        range: StatsRange.last30,
        launchDates: launchDates,
        now: now,
      );
      expect(s.launchCount, 2);
      expect(s.launchCountFiltered, isTrue);
    });

    test('不传 launchDates → 使用原值且未过滤', () {
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 42,
        range: StatsRange.last30,
        now: now,
      );
      expect(s.launchCount, 42);
      expect(s.launchCountFiltered, isFalse);
    });
  });

  group('8. 周期对比（previous）', () {
    test('last30 同时计算上一周期快照', () {
      // 当前窗口 [2026-08-17, 2026-09-15]
      // 上一窗口 [2026-07-18, 2026-08-16]
      final messages = [
        // 当前窗口 3 条
        _msg(
            id: 'c1',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 1)),
        _msg(
            id: 'c2',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 5)),
        _msg(
            id: 'c3',
            conversationId: 'c1',
            timestamp: DateTime(2026, 9, 10)),
        // 上一窗口 2 条
        _msg(
            id: 'p1',
            conversationId: 'c1',
            timestamp: DateTime(2026, 7, 20)),
        _msg(
            id: 'p2',
            conversationId: 'c1',
            timestamp: DateTime(2026, 8, 10)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.last30,
        now: now,
      );
      expect(s.messageCount, 3);
      expect(s.previous, isNotNull);
      expect(s.previous!.messageCount, 2);
      // 上一周期不再嵌套 previous
      expect(s.previous!.previous, isNull);
    });

    test('all 区间 → previous == null', () {
      final messages = [
        _msg(id: 'm1', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.previous, isNull);
    });
  });

  group('9. topicRows 上限', () {
    // 构造 25 个会话，各带不等数量的 messageIds。
    List<Conversation> _buildConvos() {
      return [
        for (var i = 0; i < 25; i++)
          _convo(
            id: 'topic-$i',
            createdAt: DateTime(2026, 9, 1),
            title: '话题$i',
            messageIds: ['m$i-1', 'm$i-2'],
          ),
      ];
    }

    test('topicLimit=20 → topicRows.length == 20', () {
      final s = StatsSnapshot.compute(
        conversations: _buildConvos(),
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        topicLimit: 20,
        now: now,
      );
      expect(s.topicRows.length, 20);
    });

    test('topicLimit=5 → topicRows.length == 5', () {
      final s = StatsSnapshot.compute(
        conversations: _buildConvos(),
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        topicLimit: 5,
        now: now,
      );
      expect(s.topicRows.length, 5);
    });

    test('默认 topicLimit=20', () {
      final s = StatsSnapshot.compute(
        conversations: _buildConvos(),
        messages: const <ChatMessage>[],
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.topicRows.length, 20);
    });
  });

  group('10. messagesByDay 聚合', () {
    test('同一天多条消息按日累加', () {
      final messages = [
        _msg(id: 'd1-1', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
        _msg(id: 'd1-2', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
        _msg(id: 'd1-3', conversationId: 'c1', timestamp: DateTime(2026, 9, 1)),
        _msg(id: 'd2-1', conversationId: 'c1', timestamp: DateTime(2026, 9, 5)),
        _msg(id: 'd2-2', conversationId: 'c1', timestamp: DateTime(2026, 9, 5)),
      ];
      final s = StatsSnapshot.compute(
        conversations: emptyConvos,
        messages: messages,
        assistants: emptyAssistants,
        launchCount: 0,
        range: StatsRange.all,
        now: now,
      );
      expect(s.messagesByDay[DateTime(2026, 9, 1)], 3);
      expect(s.messagesByDay[DateTime(2026, 9, 5)], 2);
      expect(s.messagesByDay.length, 2);
    });
  });
}
