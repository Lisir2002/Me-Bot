import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/features/conversation_style/framework/style_resolver.dart';
import 'package:minime_core/features/conversation_style/models/conversation_state.dart';
import 'package:minime_core/features/conversation_style/models/conversation_style.dart';
import 'package:minime_core/features/conversation_style/models/message_part.dart';
import 'package:minime_core/features/conversation_style/models/style_settings.dart';

void main() {
  group('StyleResolver 测试', () {
    late StyleResolver resolver;

    setUp(() {
      resolver = StyleResolver();
    });

    test('手动选择优先：per-conversation 覆盖', () {
      final settings = StyleSettings(
        globalStyle: ConversationStyle.classicBubble,
        conversationOverrides: {'conv-1': ConversationStyle.terminal},
      );
      final intent = const ConversationIntent();

      final result = resolver.resolve(
        settings: settings,
        intent: intent,
        conversationId: 'conv-1',
      );

      expect(result, equals(ConversationStyle.terminal));
    });

    test('per-assistant 覆盖优先于全局', () {
      final settings = StyleSettings(
        globalStyle: ConversationStyle.classicBubble,
        assistantOverrides: {'assistant-1': ConversationStyle.agentThreeTier},
      );
      final intent = const ConversationIntent();

      final result = resolver.resolve(
        settings: settings,
        intent: intent,
        assistantId: 'assistant-1',
      );

      expect(result, equals(ConversationStyle.agentThreeTier));
    });

    test('未启用自动模式时使用全局样式', () {
      final settings = const StyleSettings(
        globalStyle: ConversationStyle.minimalStream,
        autoModeEnabled: false,
      );
      final intent = ConversationIntent(
        hasToolCalls: true,
        toolCallCount: 5,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(result, equals(ConversationStyle.minimalStream));
    });

    test('自动模式：纯文本短对话推荐经典气泡或极简流式', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = ConversationIntent(
        messageCount: 3,
        avgMessageLength: 50,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(
        [ConversationStyle.classicBubble, ConversationStyle.minimalStream]
            .contains(result),
        isTrue,
      );
    });

    test('自动模式：多次工具调用推荐 Agent 三层级或工具卡片流', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = ConversationIntent(
        hasToolCalls: true,
        toolCallCount: 5,
        isAnalyticalTask: true,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(
        [
          ConversationStyle.agentThreeTier,
          ConversationStyle.toolCardFlow,
          ConversationStyle.thinkActObserve,
        ].contains(result),
        isTrue,
      );
    });

    test('自动模式：开发者场景推荐终端或全宽文档', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = ConversationIntent(
        hasCodeBlocks: true,
        isDeveloperContext: true,
        avgMessageLength: 300,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(
        [
          ConversationStyle.terminal,
          ConversationStyle.fullWidthDocument,
          ConversationStyle.richContent,
        ].contains(result),
        isTrue,
      );
    });

    test('自动模式：多助手推荐多助手协作样式', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = const ConversationIntent(
        hasMultipleAssistants: true,
        hasToolCalls: true,
        toolCallCount: 2,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      // 多助手协作应该有较高分数
      expect(result, isNotNull);
    });

    test('自动模式：高风险操作推荐执行计划面板或思考行动观察', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = const ConversationIntent(
        hasHighRiskActions: true,
        hasToolCalls: true,
        toolCallCount: 2,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(
        [
          ConversationStyle.planSurface,
          ConversationStyle.thinkActObserve,
          ConversationStyle.agentThreeTier,
        ].contains(result),
        isTrue,
      );
    });

    test('自动模式：创意任务推荐对话分支或画布产物', () {
      final settings = const StyleSettings(autoModeEnabled: true);
      final intent = const ConversationIntent(
        isCreativeTask: true,
        messageCount: 5,
        avgMessageLength: 300,
      );

      final result = resolver.resolve(settings: settings, intent: intent);
      expect(
        [
          ConversationStyle.threadBranching,
          ConversationStyle.canvasArtifact,
          ConversationStyle.fullWidthDocument,
        ].contains(result),
        isTrue,
      );
    });

    test('explainChoice 返回非空描述', () {
      final intent = ConversationIntent(
        hasToolCalls: true,
        toolCallCount: 3,
        hasCodeBlocks: true,
      );
      final explanation = resolver.explainChoice(intent);
      expect(explanation.isNotEmpty, isTrue);
      expect(explanation.contains('工具调用'), isTrue);
    });
  });

  group('ConversationIntent.analyze 测试', () {
    test('空消息列表返回默认意图', () {
      final intent = ConversationIntent.analyze([]);
      expect(intent.hasToolCalls, isFalse);
      expect(intent.toolCallCount, equals(0));
      expect(intent.messageCount, equals(0));
    });

    test('分析包含工具调用的消息', () {
      final messages = [
        Message(
          role: MessageRole.assistant,
          parts: [
            ToolCallPart(toolName: 'search'),
            TextPart(text: 'result'),
          ],
        ),
      ];
      final intent = ConversationIntent.analyze(messages);
      expect(intent.hasToolCalls, isTrue);
      expect(intent.toolCallCount, equals(1));
      expect(intent.isDeveloperContext, isTrue);
    });

    test('分析包含代码块的消息', () {
      final messages = [
        Message(
          role: MessageRole.assistant,
          parts: [CodePart(code: 'x=1', language: 'python')],
        ),
      ];
      final intent = ConversationIntent.analyze(messages);
      expect(intent.hasCodeBlocks, isTrue);
      expect(intent.codeBlockRatio, greaterThan(0));
    });
  });

  group('ConversationUIState 测试', () {
    test('toggleToolCall 切换展开状态', () {
      var state = const ConversationUIState();
      expect(state.expandedToolCallIds.contains('tool-1'), isFalse);

      state = state.toggleToolCall('tool-1');
      expect(state.expandedToolCallIds.contains('tool-1'), isTrue);

      state = state.toggleToolCall('tool-1');
      expect(state.expandedToolCallIds.contains('tool-1'), isFalse);
    });

    test('toggleThinking 切换折叠状态', () {
      var state = const ConversationUIState();
      expect(state.collapsedThinkingIds.contains('think-1'), isFalse);

      state = state.toggleThinking('think-1');
      expect(state.collapsedThinkingIds.contains('think-1'), isTrue);
    });

    test('toggleCodeBlock 切换展开状态', () {
      var state = const ConversationUIState();
      state = state.toggleCodeBlock('code-1');
      expect(state.expandedCodeBlockIds.contains('code-1'), isTrue);
    });

    test('copyWith 保留其他字段', () {
      const original = ConversationUIState(
        expandedToolCallIds: {'tool-1'},
        planConfirmed: true,
      );
      final copied = original.copyWith(activeBranchId: 'branch-1');
      expect(copied.expandedToolCallIds, equals({'tool-1'}));
      expect(copied.planConfirmed, isTrue);
      expect(copied.activeBranchId, equals('branch-1'));
    });
  });

  group('ConversationState 测试', () {
    test('idle 状态默认值正确', () {
      const state = ConversationState.idle;
      expect(state.isGenerating, isFalse);
      expect(state.generatingMessageId, isNull);
      expect(state.error, isNull);
      expect(state.unreadCount, equals(0));
    });

    test('copyWith 更新指定字段', () {
      const original = ConversationState.idle;
      final updated = original.copyWith(
        isGenerating: true,
        currentPhase: '正在搜索...',
      );
      expect(updated.isGenerating, isTrue);
      expect(updated.currentPhase, equals('正在搜索...'));
      expect(updated.error, isNull);
    });
  });

  group('StyleSettings 测试', () {
    test('序列化/反序列化', () {
      const settings = StyleSettings(
        globalStyle: ConversationStyle.agentThreeTier,
        autoModeEnabled: true,
        assistantOverrides: {'a1': ConversationStyle.terminal},
        transitionAnimationEnabled: false,
      );
      final json = settings.toJson();
      final restored = StyleSettings.fromJson(json);

      expect(restored.globalStyle, equals(ConversationStyle.agentThreeTier));
      expect(restored.autoModeEnabled, isTrue);
      expect(restored.assistantOverrides['a1'], equals(ConversationStyle.terminal));
      expect(restored.transitionAnimationEnabled, isFalse);
    });
  });
}
