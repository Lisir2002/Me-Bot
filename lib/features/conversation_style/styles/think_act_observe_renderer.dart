// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';

import '../data/conversation_data_source.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 07：思考-行动-观察闭环（Think-Act-Observe）
///
/// 左侧 rail 时间线，三阶段明确区分：
///   思考 Think  —— 紫色 Icons.psychology
///   行动 Act    —— 蓝色 Icons.build
///   观察 Observe—— 绿色 Icons.visibility
/// 将每条助手消息的 parts 按类型分组到三个阶段，文本回答作为最终结论显示在闭环之后。
class ThinkActObserveRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.thinkActObserve;

  @override
  Widget build(BuildContext context) {
    return _TaoView(
      dataSource: dataSource,
      initialUiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }
}

class _TaoView extends StatefulWidget {
  final ConversationDataSource dataSource;
  final ConversationUIState initialUiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _TaoView({
    required this.dataSource,
    required this.initialUiState,
    required this.onUIStateChanged,
  });

  @override
  State<_TaoView> createState() => _TaoViewState();
}

class _TaoViewState extends State<_TaoView> {
  late ConversationUIState _uiState;

  @override
  void initState() {
    super.initState();
    _uiState = widget.initialUiState;
  }

  void _update(ConversationUIState s) {
    setState(() => _uiState = s);
    widget.onUIStateChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: widget.dataSource.messageStream,
      initialData: widget.dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        if (messages.isEmpty) return const Center(child: Text('暂无消息'));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  Widget _buildMessage(BuildContext context, Message message) {
    if (message.role == MessageRole.user) {
      return _UserRow(message: message);
    }
    if (message.role == MessageRole.system) {
      return _SystemRow(text: message.textContent);
    }

    // 按类型把 parts 分组到三阶段
    final think = message.parts.whereType<ThinkingPart>().toList();
    final act = message.parts
        .where((p) => p is ToolCallPart || p is ApprovalPart)
        .toList();
    // 观察阶段：从已完成的工具结果派生结果分析
    final observeResults = message.parts
        .whereType<ToolCallPart>()
        .where((t) => t.result != null)
        .toList();
    // 最终结论：文本与代码等非闭环内容
    final conclusion = message.parts
        .where((p) =>
            p is TextPart || p is CodePart || p is ImagePart || p is FilePart || p is ArtifactPart)
        .toList();

    final stages = <Widget>[];

    if (think.isNotEmpty) {
      stages.add(_StageRail(
        color: const Color(0xFF8E44AD),
        icon: Icons.psychology,
        label: '思考 Think',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: think
              .map((t) => ThinkingPartRenderer(
                    part: t,
                    collapsed: _uiState.collapsedThinkingIds.contains(t.id),
                    onToggleCollapse: () => _update(_uiState.toggleThinking(t.id)),
                  ))
              .toList(),
        ),
      ));
    }

    if (act.isNotEmpty) {
      stages.add(_StageRail(
        color: Colors.blue,
        icon: Icons.build,
        label: '行动 Act',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: act.map((p) {
            if (p is ToolCallPart) {
              return _ActToolCard(
                part: p,
                expanded: _uiState.expandedToolCallIds.contains(p.id),
                onToggle: () => _update(_uiState.toggleToolCall(p.id)),
              );
            } else if (p is ApprovalPart) {
              return ApprovalPartRenderer(
                part: p,
                onApprove: () => widget.dataSource.approveAction(p.id),
                onReject: () => widget.dataSource.rejectAction(p.id),
              );
            }
            return const SizedBox.shrink();
          }).toList(),
        ),
      ));
    }

    if (observeResults.isNotEmpty) {
      stages.add(_StageRail(
        color: Colors.green,
        icon: Icons.visibility,
        label: '观察 Observe',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: observeResults.map((t) => _ObserveCard(part: t)).toList(),
        ),
      ));
    }

    // 三阶段闭环后：最终结论
    if (conclusion.isNotEmpty) {
      stages.add(Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: conclusion
              .map((p) => MessagePartRenderer(
                    part: p,
                    uiState: _uiState,
                    onUIStateChanged: _update,
                  ))
              .toList(),
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: stages,
      ),
    );
  }
}

/// 三阶段 rail 行：圆形图标节点 + 4px 彩色连接线 + 内容
class _StageRail extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Widget content;

  const _StageRail({
    required this.color,
    required this.icon,
    required this.label,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4px 宽彩色 rail + 圆形图标节点
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              Expanded(
                child: Container(width: 4, color: color.withValues(alpha: 0.4)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 行动阶段工具卡片：显示参数校验状态（参数数量、类型）
class _ActToolCard extends StatelessWidget {
  final ToolCallPart part;
  final bool expanded;
  final VoidCallback onToggle;

  const _ActToolCard({
    required this.part,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final argCount = part.arguments.length;
    // 简单参数校验：统计各参数值的类型
    final typeCounts = <String, int>{};
    part.arguments.forEach((k, v) {
      final t = v.runtimeType.toString();
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    });
    final summary = typeCounts.entries
        .map((e) => '${e.value}× ${e.key}')
        .join(' · ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 14, color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(part.toolName,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  ),
                  Text('$argCount 参数',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(summary.isEmpty ? '无参数' : summary,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('校验：通过 $argCount 个参数类型',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 观察阶段结果卡片：结果摘要 + 质量评分（如果有）
class _ObserveCard extends StatelessWidget {
  final ToolCallPart part;
  const _ObserveCard({required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 尝试从结果中提取质量评分
    double? score;
    if (part.result is Map) {
      final m = part.result as Map;
      final raw = m['qualityScore'] ?? m['score'] ?? m['rating'];
      if (raw is num) score = raw.toDouble();
    }
    final summary = part.result.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text('结果分析 · ${part.toolName}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('评分 ${score.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary.length > 300 ? '${summary.substring(0, 300)}…' : summary,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Message message;
  const _UserRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(message.textContent,
            style: TextStyle(color: theme.colorScheme.onPrimary)),
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  final String text;
  const _SystemRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      child: Text('[system] $text',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic)),
    );
  }
}
