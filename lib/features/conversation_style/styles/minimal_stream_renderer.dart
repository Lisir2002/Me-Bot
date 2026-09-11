// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 03: 极简流式渲染器
///
/// 布局特点：
/// - 纯文本流，无气泡无边框无头像
/// - 不显示时间戳
/// - 用户消息右对齐纯文本（灰色），助手消息左对齐正文
/// - 连续工具调用聚合为单行紧凑状态行（最少视觉元素）
/// - 思考过程用 ThinkingPartRenderer，但即使流式中也保持折叠
///   （只显示一行脉冲点 + "思考中"，不展开全文）
/// - 用户消息带引用时显示极简小字提示 "↩ 引用了消息"
/// - 代码块用等宽字体，无装饰（简单 Container + 背景色）
/// - 流式输出 StreamingCursor 紧跟最后文本，无额外装饰
///
/// 适用场景：快速问答、实时流式输出、专注阅读
/// 信息密度最低，追求最快的流式渲染性能
class MinimalStreamRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.minimalStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  /// 构建单条消息 —— 极简纯文本流
  Widget _buildMessage(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        // 用户消息右对齐，助手消息左对齐
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _buildParts(context, message, isUser, theme),
      ),
    );
  }

  /// 构建消息内部的所有 part（极简模式）
  List<Widget> _buildParts(
      BuildContext context, Message message, bool isUser, ThemeData theme) {
    final children = <Widget>[];

    // 用户消息引用提示：极简小字灰色（不需要被引用消息的内容）
    if (isUser && message.referencedMessageId != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '↩ 引用了消息',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ));
    }

    // 最后一个 TextPart 的下标（用于在其后附加流式光标）
    var lastTextIndex = -1;
    for (var i = 0; i < message.parts.length; i++) {
      if (message.parts[i] is TextPart) lastTextIndex = i;
    }

    // 连续工具调用聚合缓冲
    final pendingTools = <ToolCallPart>[];
    void flushTools() {
      if (pendingTools.isNotEmpty) {
        children.add(_buildCompactToolGroup(context, pendingTools, theme));
        pendingTools.clear();
      }
    }

    for (var i = 0; i < message.parts.length; i++) {
      final part = message.parts[i];
      switch (part) {
        case TextPart():
          flushTools();
          // 用户消息灰色右对齐，助手消息正常文本
          children.add(TextPartRenderer(
            part: part,
            textAlign: isUser ? TextAlign.right : null,
            style: isUser
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ));
          // 流式助手消息：最后一个 TextPart 后附加光标
          if (message.isStreaming && !isUser && i == lastTextIndex) {
            children.add(const StreamingCursor());
          }
        case CodePart():
          flushTools();
          // 极简代码块：等宽字体 + 简单背景
          children.add(_buildMinimalCode(context, part, theme));
        case ToolCallPart():
          // 累积连续工具调用，稍后聚合为单行紧凑状态
          pendingTools.add(part);
        case ThinkingPart():
          flushTools();
          // 极简：用 ThinkingPartRenderer，但流式中也保持折叠
          final isCollapsed =
              uiState.collapsedThinkingIds.contains(part.id);
          children.add(ThinkingPartRenderer(
            part: part,
            collapsed: isCollapsed,
            isStreaming: message.isStreaming,
            streamingCollapsed: true,
            onToggleCollapse: () => updateUIState(
              uiState.toggleThinking(part.id),
            ),
          ));
        case ApprovalPart():
          flushTools();
          children.add(ApprovalPartRenderer(
            part: part,
            onApprove: () => dataSource.approveAction(part.id),
            onReject: () => dataSource.rejectAction(part.id),
          ));
        case ImagePart():
          flushTools();
          children.add(ImagePartRenderer(part: part));
        case FilePart():
          flushTools();
          children.add(FilePartRenderer(part: part));
        case ArtifactPart():
          flushTools();
          children.add(ArtifactPartRenderer(part: part));
        case TaskPart():
          flushTools();
          children.add(Text('📋 ${part.title}'));
      }
    }
    flushTools();

    return children;
  }

  /// 极简工具调用分组状态行 —— 单行紧凑展示连续工具调用
  ///
  /// 单个工具："🔧 正在调用 web_search · 120ms"
  /// 多个连续工具："✅ web_search ×3 · 450ms"
  Widget _buildCompactToolGroup(
      BuildContext context, List<ToolCallPart> tools, ThemeData theme) {
    final hasError =
        tools.any((t) => t.status == ToolCallStatus.error);
    final hasRunning = tools.any((t) =>
        t.status == ToolCallStatus.running ||
        t.status == ToolCallStatus.pending);
    final name = tools.first.toolName;
    final label = tools.length > 1 ? '$name ×${tools.length}' : name;
    final ms = tools
        .where((t) => t.duration != null)
        .fold<int>(0, (sum, t) => sum + t.duration!.inMilliseconds);

    String emoji;
    String verb;
    if (hasError) {
      emoji = '❌';
      verb = '失败';
    } else if (hasRunning) {
      emoji = '🔧';
      verb = '调用中';
    } else {
      emoji = '✅';
      verb = '完成';
    }

    final text = ms > 0 ? '$emoji $verb $label · ${ms}ms' : '$emoji $verb $label';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }

  /// 极简代码块 —— 无装饰，仅背景色 + 等宽字体
  Widget _buildMinimalCode(
      BuildContext context, CodePart part, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            part.language,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            part.code,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
