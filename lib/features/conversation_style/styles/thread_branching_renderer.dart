// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../../../shared/widgets/snackbar.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// no_raw_alert_dialog 白名单：分支对比弹窗为分支消息 diff 内容（非确认/输入类，AppDialog 语义不符）。

/// 分支标签模型
class _Branch {
  /// 分支 ID（存入 uiState.activeBranchId）
  final String id;

  /// 显示名
  final String label;

  /// 对应 version 编号
  final int version;

  const _Branch({
    required this.id,
    required this.label,
    required this.version,
  });
}

/// Style 12: 对话分支渲染器
///
/// 设计理念：从某条消息分叉出多个路径，Git 式分支管理。
/// 利用 Message.groupId 与 Message.version 字段。
/// 无分支数据时退化为普通列表 + "暂无分支"提示。
class ThreadBranchingRenderer extends BaseStyleRenderer {
  @override
  ConversationStyle get style => ConversationStyle.threadBranching;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        final branches = _buildBranches(messages);
        final hasBranches = branches.length > 1;
        final activeVersion = _activeBranch(branches).version;

        return Column(
          children: [
            _BranchBar(
              branches: branches,
              activeId: uiState.activeBranchId ?? 'main',
              hasBranches: hasBranches,
              onSelect: (id) =>
                  updateUIState(uiState.copyWith(activeBranchId: id)),
              onCompare: (branch) =>
                  _showCompare(context, messages, branch),
              onMerge: () =>
                  showAppSnackBar(context, message: '合并主干功能占位：已请求合并'),
            ),
            Expanded(
              child: hasBranches
                  ? _buildBranchList(context, messages, activeVersion)
                  : _buildPlainList(context, messages),
            ),
          ],
        );
      },
    );
  }

  /// 构建分支集合：主干（v0）+ 每个出现的 version>0
  List<_Branch> _buildBranches(List<Message> messages) {
    final versions = <int>{0};
    for (final m in messages) {
      if (m.role != MessageRole.user && m.groupId != null) {
        versions.add(m.version);
      }
    }
    final sorted = versions.toList()..sort();
    return [
      for (final v in sorted)
        _Branch(
          id: v == 0 ? 'main' : 'v$v',
          label: v == 0 ? '主干' : '分支 v$v',
          version: v,
        ),
    ];
  }

  _Branch _activeBranch(List<_Branch> branches) {
    final id = uiState.activeBranchId;
    return branches.firstWhere(
      (b) => b.id == id,
      orElse: () => branches.first,
    );
  }

  /// 某 groupId 是否存在多个版本（真正的分叉点）
  Set<String> _branchedGroupIds(List<Message> messages) {
    final map = <String, Set<int>>{};
    for (final m in messages) {
      if (m.groupId != null) {
        (map[m.groupId!] ??= {}).add(m.version);
      }
    }
    return map.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();
  }

  Widget _buildBranchList(
      BuildContext context, List<Message> messages, int activeVersion) {
    final branchedGroups = _branchedGroupIds(messages);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isBranched =
            message.groupId != null && branchedGroups.contains(message.groupId);
        final isActiveVersion = message.version == activeVersion;
        final dimmed = isBranched && !isActiveVersion;

        return Opacity(
          opacity: dimmed ? 0.45 : 1.0,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧分支连接线
                SizedBox(
                  width: 24,
                  child: CustomPaint(
                    painter: _BranchLinePainter(
                      isCurrent: isBranched && isActiveVersion,
                      isUser: message.role == MessageRole.user,
                      branchVersion: message.version,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dimmed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('在分支 v${message.version} 中',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ),
                      _MessageCard(message: message, uiState: uiState, update: updateUIState),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 无分支时的退化列表
  Widget _buildPlainList(BuildContext context, List<Message> messages) {
    return ListView.builder(
      padding: constSymmetric,
      itemCount: messages.length,
      itemBuilder: (context, index) =>
          _MessageCard(message: messages[index], uiState: uiState, update: updateUIState),
    );
  }

  /// 分支对比对话框：并排展示主干与选中版本
  void _showCompare(
      BuildContext context, List<Message> messages, _Branch branch) {
    final groupMsgs = messages
        .where((m) =>
            m.groupId != null &&
            (m.version == 0 || m.version == branch.version))
        .toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('对比：主干 vs ${branch.label}'),
        content: SizedBox(
          width: double.maxFinite,
          child: groupMsgs.isEmpty
              ? const Text('该分支暂无内容')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in groupMsgs)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: m.version == 0
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '[v${m.version}] ${m.textContent}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }
}

/// 常量简化
const constSymmetric = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

/// 顶部分支切换栏
class _BranchBar extends StatelessWidget {
  final List<_Branch> branches;
  final String activeId;
  final bool hasBranches;
  final void Function(String id) onSelect;
  final void Function(_Branch branch) onCompare;
  final VoidCallback onMerge;

  const _BranchBar({
    required this.branches,
    required this.activeId,
    required this.hasBranches,
    required this.onSelect,
    required this.onCompare,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: branches.map((b) {
                      final isActive = b.id == activeId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onLongPress: () => onCompare(b),
                          child: ChoiceChip(
                            label: Text(b.label),
                            selected: isActive,
                            onSelected: (_) => onSelect(b.id),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (hasBranches)
                TextButton.icon(
                  onPressed: onMerge,
                  icon: const Icon(Icons.merge, size: 16),
                  label: const Text('合并主干'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          if (!hasBranches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Text('暂无分支',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// 分支树连接线画笔
class _BranchLinePainter extends CustomPainter {
  final bool isCurrent;
  final bool isUser;
  final int branchVersion;

  _BranchLinePainter({
    required this.isCurrent,
    required this.isUser,
    required this.branchVersion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isCurrent ? Colors.blue : Colors.grey
      ..strokeWidth = 2;
    final centerX = size.width / 2;
    // 竖线
    canvas.drawLine(
        Offset(centerX, 0), Offset(centerX, size.height), paint);
    // 圆点
    final dotColor = isUser
        ? Colors.teal
        : (branchVersion == 0 ? Colors.blue : Colors.orange);
    final dot = Paint()..color = dotColor;
    canvas.drawCircle(Offset(centerX, size.height / 2), isCurrent ? 5 : 3.5,
        dot);
  }

  @override
  bool shouldRepaint(covariant _BranchLinePainter old) =>
      old.isCurrent != isCurrent ||
      old.branchVersion != branchVersion ||
      old.isUser != isUser;
}

/// 普通消息卡片（复用共享 part 渲染器）
class _MessageCard extends StatelessWidget {
  final Message message;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) update;

  const _MessageCard({
    required this.message,
    required this.uiState,
    required this.update,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: message.parts
              .map((p) => MessagePartRenderer(
                    part: p,
                    uiState: uiState,
                    onUIStateChanged: update,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
