import 'package:flutter/material.dart';
import '../../../l10n/build_context_l10n.dart';
import '../models/conversation_state.dart';
import '../models/message_part.dart';

/// ==========================================================================
/// Agent 场景增强组件集
///
/// 基于深度竞品研究提炼的设计模式：
/// - TaskListRenderer：Windsurf Cascade Todo List 模式
/// - PipelineProgress：LangGraph GenUI 流水线进度
/// - FollowUpChips：Perplexity 追问建议芯片
/// - ConfidenceBadge：Devin 信心指示器（交通灯）
/// - StalledToolWarning：Cursor 停滞检测警告
/// - ToolProgressBar：Claude Code 工具执行进度条
/// ==========================================================================

/// 任务列表渲染器（Todo List）
///
/// 参考 Windsurf Cascade 的 Todo List 设计：
/// 在对话流中嵌入可勾选的任务列表，每项 ⬜/⏳/☑/✗ 状态。
/// 用于 Agent 三层级样式的中间层。
class TaskListRenderer extends StatelessWidget {
  /// 任务列表
  final List<TaskPart> tasks;

  /// 任务列表标题（可选，默认 "任务计划"）
  final String? title;

  /// 是否可交互（点击切换状态）
  final bool interactive;

  /// 任务状态切换回调
  final void Function(TaskPart task, TaskStatus newStatus)? onStatusChanged;

  const TaskListRenderer({
    super.key,
    required this.tasks,
    this.title,
    this.interactive = false,
    this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final completedCount = tasks.where((t) => t.isCompleted).length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行：任务计划 · 已完成 X/Y
          Row(
            children: [
              Icon(Icons.task_alt, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                title ?? '任务计划',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$completedCount/${tasks.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条
          LinearProgressIndicator(
            value: tasks.isEmpty ? 0 : completedCount / tasks.length,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 8),
          // 任务项列表
          ...tasks.map((task) => _TaskItem(
                task: task,
                interactive: interactive,
                onStatusChanged: onStatusChanged,
              )),
        ],
      ),
    );
  }
}

/// 单个任务项
class _TaskItem extends StatelessWidget {
  final TaskPart task;
  final bool interactive;
  final void Function(TaskPart task, TaskStatus newStatus)? onStatusChanged;

  const _TaskItem({
    required this.task,
    required this.interactive,
    this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, iconColor, textColor, bgColor) = _statusStyle(theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: interactive ? _handleTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // 状态图标
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              // 任务标题
              Expanded(
                child: Text(
                  task.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: task.isInProgress ? FontWeight.w600 : FontWeight.w400,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              // 耗时
              if (task.duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${task.duration!.inSeconds}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap() {
    if (onStatusChanged == null) return;
    // 点击循环：pending → inProgress → completed → pending
    final next = switch (task.status) {
      TaskStatus.pending => TaskStatus.inProgress,
      TaskStatus.inProgress => TaskStatus.completed,
      TaskStatus.completed => TaskStatus.pending,
      TaskStatus.failed => TaskStatus.pending,
      TaskStatus.skipped => TaskStatus.pending,
    };
    onStatusChanged!(task, next);
  }

  (IconData, Color, Color, Color?) _statusStyle(ThemeData theme) {
    switch (task.status) {
      case TaskStatus.pending:
        return (
          Icons.radio_button_unchecked,
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.onSurface,
          null,
        );
      case TaskStatus.inProgress:
        return (
          Icons.autorenew,
          Colors.blue,
          theme.colorScheme.onSurface,
          Colors.blue.withValues(alpha: 0.06),
        );
      case TaskStatus.completed:
        return (
          Icons.check_circle,
          Colors.green,
          theme.colorScheme.onSurfaceVariant,
          Colors.green.withValues(alpha: 0.06),
        );
      case TaskStatus.failed:
        return (
          Icons.error,
          theme.colorScheme.error,
          theme.colorScheme.error,
          theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        );
      case TaskStatus.skipped:
        return (
          Icons.remove_circle_outline,
          Colors.grey,
          theme.colorScheme.onSurfaceVariant,
          null,
        );
    }
  }
}

/// 流水线进度指示器
///
/// 参考 LangGraph GenUI 的 PipelineProgress：
/// 顶部横向步骤徽章，节点间连线。
/// pending=灰 / running=蓝pulse / complete=绿 / error=红。
class PipelineProgress extends StatelessWidget {
  /// 总步骤数
  final int totalSteps;

  /// 已完成步骤数
  final int completedSteps;

  /// 当前步骤名称（可选）
  final String? currentStepName;

  /// 步骤名称列表（可选，用于显示每个步骤的标签）
  final List<String>? stepNames;

  /// 是否有错误
  final bool hasError;

  const PipelineProgress({
    super.key,
    required this.totalSteps,
    required this.completedSteps,
    this.currentStepName,
    this.stepNames,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (totalSteps <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 步骤节点行
          Row(
            children: List.generate(totalSteps, (i) {
              final isComplete = i < completedSteps;
              final isCurrent = i == completedSteps && !hasError;
              final isError = hasError && i == completedSteps;

              Color nodeColor;
              IconData nodeIcon;
              if (isError) {
                nodeColor = theme.colorScheme.error;
                nodeIcon = Icons.error;
              } else if (isComplete) {
                nodeColor = Colors.green;
                nodeIcon = Icons.check;
              } else if (isCurrent) {
                nodeColor = Colors.blue;
                nodeIcon = Icons.circle;
              } else {
                nodeColor = Colors.grey;
                nodeIcon = Icons.radio_button_unchecked;
              }

              return Expanded(
                child: Row(
                  children: [
                    // 节点
                    isCurrent
                        ? _PulsingNode(color: nodeColor, icon: nodeIcon)
                        : Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isComplete || isError ? nodeColor : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(color: nodeColor, width: 2),
                            ),
                            child: Icon(nodeIcon, size: 12, color: isComplete || isError ? Colors.white : nodeColor),
                          ),
                    // 连接线（最后一个节点后不画）
                    if (i < totalSteps - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i < completedSteps ? Colors.green : theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          // 当前步骤名称
          if (currentStepName != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (hasError)
                  Icon(Icons.error, size: 12, color: theme.colorScheme.error)
                else
                  const _PulsingDot(color: Colors.blue, size: 8),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentStepName!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasError ? theme.colorScheme.error : Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$completedSteps/$totalSteps',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 脉冲节点（进行中步骤）
class _PulsingNode extends StatefulWidget {
  final Color color;
  final IconData icon;
  const _PulsingNode({required this.color, required this.icon});

  @override
  State<_PulsingNode> createState() => _PulsingNodeState();
}

class _PulsingNodeState extends State<_PulsingNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.3 + 0.7 * _controller.value),
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2),
          ),
          child: Icon(widget.icon, size: 12, color: Colors.white),
        );
      },
    );
  }
}

/// 脉冲小圆点
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, required this.size});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: 0.3 + 0.7 * _controller.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

/// 追问建议芯片
///
/// 参考 Perplexity 的 Follow-up 设计：
/// 每个答案后给 3-4 个上下文相关的追问芯片，点击即问。
class FollowUpChips extends StatelessWidget {
  /// 追问建议列表
  final List<String> suggestions;

  /// 点击回调
  final void Function(String suggestion)? onTap;

  const FollowUpChips({
    super.key,
    required this.suggestions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                // 冻结映射未提供「继续追问」键，沿用字面量（行级豁免）
                // ignore: hardcoded_ui_string
                '继续追问',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: suggestions.map((s) {
              return ActionChip(
                label: Text(
                  s,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                ),
                onPressed: onTap != null ? () => onTap!(s) : null,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// 信心徽章
///
/// 参考 Devin 的信心指示器：🟢🟡🔴 交通灯系统。
/// Agent 在关键决策点自我评估信心，低信心时建议暂停等待确认。
class ConfidenceBadge extends StatelessWidget {
  final ConfidenceLevel level;

  const ConfidenceBadge({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (level) {
      ConfidenceLevel.high => (Colors.green, Icons.check_circle, '高信心'),
      ConfidenceLevel.medium => (Colors.orange, Icons.help_outline, '中信心'),
      ConfidenceLevel.low => (Theme.of(context).colorScheme.error, Icons.warning, '低信心'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具停滞警告
///
/// 参考 Cursor 社区反馈的 "spinner 永不停转" 问题：
/// 超过 N 秒无更新时显示 "仍在运行？" 提示 + 取消按钮。
class StalledToolWarning extends StatelessWidget {
  /// 停滞时长（秒）
  final int stalledSeconds;

  /// 取消回调
  final VoidCallback? onCancel;

  const StalledToolWarning({
    super.key,
    required this.stalledSeconds,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // 冻结映射未提供停滞提示键，沿用字面量（行级豁免）
              // ignore: hardcoded_ui_string
              '已运行 ${stalledSeconds}s 无更新，仍在运行？',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: const Size(0, 24),
                foregroundColor: theme.colorScheme.error,
              ),
              // 冻结映射未提供通用「取消」键，沿用字面量（行级豁免）
              // ignore: hardcoded_ui_string
              child: const Text('取消', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// 工具执行进度条
///
/// 参考 Claude Code 的 `████░░░░ 65%` 进度条设计，
/// 缓解长时间工具调用的等待焦虑。
class ToolProgressBar extends StatelessWidget {
  /// 进度（0.0 - 1.0）
  final double progress;

  /// 颜色（默认蓝色）
  final Color? color;

  const ToolProgressBar({
    super.key,
    required this.progress,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = color ?? Colors.blue;
    final clamped = progress.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 6,
              backgroundColor: barColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 10,
            color: barColor,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

/// 错误恢复建议列表
///
/// 参考 Claude Code 的错误建议化设计：
/// 错误卡片不只报错，还给出可操作建议 + 一键重试。
class ErrorRecoverySuggestions extends StatelessWidget {
  /// 建议列表
  final List<String> suggestions;

  /// 重试回调
  final VoidCallback? onRetry;

  const ErrorRecoverySuggestions({
    super.key,
    required this.suggestions,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, size: 14, color: theme.colorScheme.error),
              const SizedBox(width: 4),
              Text(
                // 冻结映射未提供「恢复建议」键，沿用字面量（行级豁免）
                // ignore: hardcoded_ui_string
                '恢复建议',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...suggestions.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: theme.colorScheme.error, fontSize: 11)),
                    Expanded(
                      child: Text(
                        s,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              )),
          if (onRetry != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 14),
                label: Text(context.l10n.commonRetry, style: const TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 28),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 任务模式切换栏
///
/// 参考 Cline 的 Plan/Act 双模式设计：
/// 对话流顶部加模式切换，Plan 只讨论，Act 才执行副作用。
class TaskModeSwitcher extends StatelessWidget {
  final TaskExecutionMode currentMode;
  final void Function(TaskExecutionMode mode)? onModeChanged;

  const TaskModeSwitcher({
    super.key,
    required this.currentMode,
    this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: TaskExecutionMode.values.map((mode) {
          final isSelected = mode == currentMode;
          final (icon, label) = switch (mode) {
            TaskExecutionMode.plan => (Icons.edit_note, '规划'),
            TaskExecutionMode.act => (Icons.play_arrow, '执行'),
            TaskExecutionMode.auto => (Icons.auto_awesome, '自动'),
          };

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: onModeChanged != null ? () => onModeChanged!(mode) : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: isSelected
                    ? BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
