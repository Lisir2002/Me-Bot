import 'dart:async';
import 'package:flutter/material.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// 单步状态
enum _StepStatus { pending, running, done, failed }

/// 解析出的计划步骤
class _PlanStep {
  final String title;
  final List<String> subtasks;
  final String estimatedTime;

  const _PlanStep({
    required this.title,
    required this.subtasks,
    required this.estimatedTime,
  });
}

/// Style 14: 执行计划面板渲染器
///
/// Agent 先展示执行计划，用户审核后执行。
/// 从 TextPart 中解析 "计划:"/"步骤:" 或数字编号列表，
/// 确认后用 Timer 模拟逐步执行。
class PlanSurfaceRenderer extends BaseStyleRenderer {
  // ---------- 本地执行状态（不持久化，随样式激活重建） ----------
  List<_PlanStep> _steps = [];
  List<_StepStatus> _statuses = [];
  bool _paused = false;
  int _cursor = 0;
  int _tick = 0;
  Timer? _timer;

  @override
  ConversationStyle get style => ConversationStyle.planSurface;

  @override
  void onDetach() {
    _timer?.cancel();
    _timer = null;
    super.onDetach();
  }

  /// 解析计划文本为步骤列表
  void _parsePlan(String source) {
    final steps = <_PlanStep>[];
    final lines = source.split('\n');
    _PlanStep? current;
    for (final raw in lines) {
      final line = raw.trim();
      // 数字编号步骤：1. / 1、
      final stepMatch =
          RegExp(r'^\d+[.、]\s*(.+)').firstMatch(line);
      if (stepMatch != null) {
        current = _PlanStep(
          title: stepMatch.group(1)!.trim(),
          subtasks: const [],
          estimatedTime: '~${(steps.length + 1) * 2} 分钟',
        );
        steps.add(current);
        continue;
      }
      // 缩进子任务：- xxx
      final subMatch = RegExp(r'^[-*•]\s*(.+)').firstMatch(line);
      if (subMatch != null && current != null) {
        current.subtasks.add(subMatch.group(1)!.trim());
      }
    }
    _steps = steps;
    _statuses = List.filled(steps.length, _StepStatus.pending);
    _cursor = 0;
    _paused = false;
  }

  /// 从消息流中提取计划来源文本
  String? _extractPlanSource(List<Message> messages) {
    for (final m in messages.reversed) {
      for (final part in m.parts) {
        if (part is TextPart) {
          final t = part.text;
          final hasNumbered =
              RegExp(r'^\s*1[.、]').hasMatch(t) &&
                  RegExp(r'^\s*2[.、]', multiLine: true).hasMatch(t);
          if (t.contains('计划:') ||
              t.contains('计划：') ||
              t.contains('步骤:') ||
              t.contains('步骤：') ||
              hasNumbered) {
            return t;
          }
        }
      }
    }
    return null;
  }

  /// 确认执行：启动模拟定时器
  void _startExecution() {
    if (_steps.isEmpty) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (_paused) return;
      if (_cursor >= _statuses.length) {
        timer.cancel();
        return;
      }
      // 当前步骤先 running，再 tick 一次置 done
      if (_statuses[_cursor] == _StepStatus.pending) {
        _statuses[_cursor] = _StepStatus.running;
      } else {
        _statuses[_cursor] = _StepStatus.done;
        _cursor++;
      }
      _tick++;
      // 借助 uiState 变化触发重建
      final gs =
          Map<String, Map<String, dynamic>>.from(uiState.generativeUiStates);
      gs['plan'] = {'tick': _tick};
      updateUIState(uiState.copyWith(generativeUiStates: gs));
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        final source = _extractPlanSource(messages);
        // 仅在步骤为空且检测到计划时解析一次
        if (_steps.isEmpty && source != null) {
          _parsePlan(source);
        }

        final hasPlan = _steps.isNotEmpty;
        final confirmed = uiState.planConfirmed;
        final doneCount =
            _statuses.where((s) => s == _StepStatus.done).length;
        final progress =
            hasPlan ? doneCount / _steps.length : 0.0;

        return Column(
          children: [
            if (hasPlan)
              _PlanPanel(
                steps: _steps,
                statuses: _statuses,
                confirmed: confirmed,
                paused: _paused,
                progress: progress,
                onConfirm: () {
                  updateUIState(uiState.copyWith(planConfirmed: true));
                  _startExecution();
                },
                onEdit: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('修改计划功能占位'))),
                onPauseResume: () {
                  setStateLocal(() => _paused = !_paused);
                },
              )
            else
              const _NoPlanHint(),
            Expanded(
              child: _buildMessageList(context, messages),
            ),
          ],
        );
      },
    );
  }

  /// 不依赖 Stateful 的本地重建：借用 uiState 触发
  void setStateLocal(void Function() mutator) {
    mutator();
    _tick++;
    final gs =
        Map<String, Map<String, dynamic>>.from(uiState.generativeUiStates);
    gs['plan'] = {'tick': _tick};
    updateUIState(uiState.copyWith(generativeUiStates: gs));
  }

  Widget _buildMessageList(BuildContext context, List<Message> messages) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final isUser = m.role == MessageRole.user;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: m.parts
                  .map((p) => MessagePartRenderer(
                        part: p,
                        uiState: uiState,
                        onUIStateChanged: updateUIState,
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

/// 计划面板卡片
class _PlanPanel extends StatelessWidget {
  final List<_PlanStep> steps;
  final List<_StepStatus> statuses;
  final bool confirmed;
  final bool paused;
  final double progress;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onPauseResume;

  const _PlanPanel({
    required this.steps,
    required this.statuses,
    required this.confirmed,
    required this.paused,
    required this.progress,
    required this.onConfirm,
    required this.onEdit,
    required this.onPauseResume,
  });

  String get _statusText {
    if (!confirmed) return '待确认';
    if (paused) return '已暂停';
    if (progress >= 1.0) return '已完成';
    return '执行中';
  }

  Color get _statusColor {
    if (!confirmed) return Colors.orange;
    if (paused) return Colors.grey;
    if (progress >= 1.0) return Colors.green;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('执行计划',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: _statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              _StepTile(
                index: i,
                step: steps[i],
                status: statuses[i],
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!confirmed) ...[
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('修改计划'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('确认执行'),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: onPauseResume,
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                        size: 16),
                    label: Text(paused ? '恢复' : '暂停'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个步骤折叠项
class _StepTile extends StatelessWidget {
  final int index;
  final _PlanStep step;
  final _StepStatus status;

  const _StepTile({
    required this.index,
    required this.step,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (status) {
      _StepStatus.pending => (Icons.radio_button_unchecked, Colors.grey),
      _StepStatus.running => (Icons.autorenew, Colors.blue),
      _StepStatus.done => (Icons.check_circle, Colors.green),
      _StepStatus.failed => (Icons.error, theme.colorScheme.error),
    };
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        leading: Icon(icon, size: 18, color: color),
        title: Text('步骤 ${index + 1}：${step.title}',
            style: theme.textTheme.bodyMedium),
        subtitle: Text('预估 ${step.estimatedTime}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        childrenPadding: const EdgeInsets.only(left: 28, bottom: 8),
        children: step.subtasks.isEmpty
            ? [
                Text('（无子任务）',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ]
            : step.subtasks
                .map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s)),
                        ],
                      ),
                    ))
                .toList(),
      ),
    );
  }
}

/// 无计划提示
class _NoPlanHint extends StatelessWidget {
  const _NoPlanHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_note, size: 32, color: Colors.grey),
          const SizedBox(height: 8),
          Text('暂无执行计划',
              style: Theme.of(context).textTheme.bodyMedium),
          Text('助手生成带"计划:"或编号列表的内容后将自动识别',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
