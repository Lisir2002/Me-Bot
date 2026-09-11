import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/features/conversation_style/models/message_part.dart';
import 'package:minime_core/features/conversation_style/models/conversation_style.dart';

void main() {
  group('MessagePart 模型测试', () {
    test('TextPart 序列化/反序列化', () {
      final part = TextPart(text: 'Hello World');
      final json = part.toJson();
      final restored = TextPart.fromJson(json);

      expect(restored.text, equals('Hello World'));
      expect(restored.id, equals(part.id));
      expect(restored.entities, isNull);
    });

    test('TextPart 带实体序列化', () {
      final part = TextPart(
        text: 'Hello **bold**',
        entities: [
          const TextEntity(type: TextEntityType.bold, offset: 6, length: 4),
        ],
      );
      final json = part.toJson();
      expect(json['entities'], isNotNull);
      expect((json['entities'] as List).length, equals(1));
    });

    test('CodePart 序列化/反序列化', () {
      final part = CodePart(
        code: 'void main() {}',
        language: 'dart',
        filename: 'main.dart',
      );
      final json = part.toJson();
      final restored = CodePart.fromJson(json);

      expect(restored.code, equals('void main() {}'));
      expect(restored.language, equals('dart'));
      expect(restored.filename, equals('main.dart'));
    });

    test('ToolCallPart 状态转换', () {
      final part = ToolCallPart(
        toolName: 'web_search',
        arguments: {'query': 'test'},
        status: ToolCallStatus.pending,
      );

      expect(part.isCompleted, isFalse);

      final running = part.copyWith(status: ToolCallStatus.running);
      expect(running.status, equals(ToolCallStatus.running));
      expect(running.isCompleted, isFalse);

      final success = running.copyWith(
        status: ToolCallStatus.success,
        result: 'search result',
        duration: const Duration(milliseconds: 1500),
      );
      expect(success.isCompleted, isTrue);
      expect(success.duration!.inSeconds, equals(1));
    });

    test('ToolCallPart 序列化/反序列化', () {
      final part = ToolCallPart(
        toolName: 'web_search',
        arguments: {'query': 'flutter'},
        status: ToolCallStatus.success,
        duration: const Duration(milliseconds: 500),
      );
      final json = part.toJson();
      final restored = ToolCallPart.fromJson(json);

      expect(restored.toolName, equals('web_search'));
      expect(restored.status, equals(ToolCallStatus.success));
      expect(restored.duration!.inMilliseconds, equals(500));
    });

    test('ThinkingPart 序列化', () {
      final part = ThinkingPart(
        content: 'Let me think...',
        tokenCount: 150,
        duration: const Duration(seconds: 3),
      );
      final json = part.toJson();
      expect(json['tokenCount'], equals(150));
      expect(json['durationMs'], equals(3000));
    });

    test('ApprovalPart 状态转换', () {
      final part = ApprovalPart(
        action: 'delete_file',
        description: '删除敏感文件',
      );
      expect(part.status, equals(ApprovalStatus.pending));

      final approved = part.copyWith(status: ApprovalStatus.approved);
      expect(approved.status, equals(ApprovalStatus.approved));
    });

    test('ArtifactPart 序列化', () {
      final part = ArtifactPart(
        artifactId: 'art_001',
        type: ArtifactType.code,
        title: 'main.dart',
        preview: 'void main()...',
      );
      final json = part.toJson();
      expect(json['artifactId'], equals('art_001'));
      expect(json['artifactType'], equals('code'));
    });

    test('ImagePart 序列化', () {
      final part = ImagePart(
        url: 'https://example.com/image.png',
        caption: '测试图片',
        width: 800,
        height: 600,
      );
      final json = part.toJson();
      expect(json['url'], equals('https://example.com/image.png'));
      expect(json['width'], equals(800));
    });

    test('FilePart 序列化', () {
      final part = FilePart(
        name: 'document.pdf',
        url: '/path/to/doc.pdf',
        size: 1024000,
        mimeType: 'application/pdf',
      );
      final json = part.toJson();
      expect(json['size'], equals(1024000));
      expect(json['mimeType'], equals('application/pdf'));
    });

    test('messagePartFromJson 类型分发', () {
      final textJson = {'type': 'text', 'text': 'hello'};
      final textPart = messagePartFromJson(textJson);
      expect(textPart, isA<TextPart>());

      final codeJson = {'type': 'code', 'code': 'x=1', 'language': 'python'};
      final codePart = messagePartFromJson(codeJson);
      expect(codePart, isA<CodePart>());

      final toolJson = {
        'type': 'tool_call',
        'toolName': 'search',
        'status': 'success'
      };
      final toolPart = messagePartFromJson(toolJson);
      expect(toolPart, isA<ToolCallPart>());
    });
  });

  group('Message 模型测试', () {
    test('Message parts 分类访问', () {
      final message = Message(
        role: MessageRole.assistant,
        parts: [
          ThinkingPart(content: '思考中'),
          TextPart(text: '回答'),
          CodePart(code: 'x=1'),
          ToolCallPart(toolName: 'search'),
          ApprovalPart(action: 'test', description: 'test'),
          ArtifactPart(artifactId: 'a1', type: ArtifactType.document, title: 'doc'),
          ImagePart(url: 'http://img.png'),
          FilePart(name: 'f.txt', url: '/f.txt', size: 10),
        ],
      );

      expect(message.thinkingParts.length, equals(1));
      expect(message.toolCalls.length, equals(1));
      expect(message.codeBlocks.length, equals(1));
      expect(message.approvals.length, equals(1));
      expect(message.artifacts.length, equals(1));
      expect(message.images.length, equals(1));
      expect(message.files.length, equals(1));
      expect(message.textContent, equals('回答'));
    });

    test('Message 序列化/反序列化', () {
      final message = Message(
        role: MessageRole.user,
        parts: [TextPart(text: '你好')],
        modelId: 'gpt-4',
        assistantName: '助手',
        assistantColor: 'blue',
      );
      final json = message.toJson();
      final restored = Message.fromJson(json);

      expect(restored.role, equals(MessageRole.user));
      expect(restored.parts.length, equals(1));
      expect(restored.modelId, equals('gpt-4'));
      expect(restored.assistantName, equals('助手'));
    });

    test('Message copyWith 保留字段', () {
      final original = Message(
        role: MessageRole.assistant,
        parts: [TextPart(text: 'original')],
        modelId: 'model-1',
      );
      final copied = original.copyWith(
        parts: [TextPart(text: 'updated')],
      );

      expect(copied.textContent, equals('updated'));
      expect(copied.modelId, equals('model-1'));
      expect(copied.role, equals(MessageRole.assistant));
    });
  });

  group('ConversationStyle 枚举测试', () {
    test('所有 9 种样式 + auto 都存在', () {
      expect(ConversationStyle.values.length, equals(10));
      expect(ConversationStyle.classicBubble.index, equals(0));
      expect(ConversationStyle.richContent.index, equals(8));
      expect(ConversationStyle.auto.index, equals(9));
    });

    test('StyleMetaRegistry 包含所有样式元信息', () {
      expect(StyleMetaRegistry.all.length, equals(9));
      expect(StyleMetaRegistry.concreteStyles.length, equals(9));

      for (final style in ConversationStyle.values) {
        if (style != ConversationStyle.auto) {
          final meta = StyleMetaRegistry.get(style);
          expect(meta.style, equals(style));
          expect(meta.displayName.isNotEmpty, isTrue);
          expect(meta.description.isNotEmpty, isTrue);
        }
      }
    });
  });
}
