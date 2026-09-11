// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../../../shared/widgets/snackbar.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../models/style_settings.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 13: 上下文面板渲染器
///
/// 对话 + 右侧固定上下文面板。宽屏 Row（对话 2/3 + 面板 1/3），
/// 窄屏（< 600）退化为底部 DraggableScrollableSheet。
/// 面板四个 Tab：文件 / 工具 / 引用来源 / 模型信息。
class ContextPanelRenderer extends BaseStyleRenderer {
  /// 本地记录的已移除文件 ID（UI 层状态）
  final Set<String> _removedFileIds = {};

  @override
  ConversationStyle get style => ConversationStyle.contextPanel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        final panel = _buildPanel(context, messages);
        final chat = _buildChat(context, messages);

        return LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: chat),
                Expanded(flex: 1, child: panel),
              ],
            );
          }
          // 窄屏：对话在上，面板为底部可拖拽 Sheet
          return Stack(
            children: [
              Positioned.fill(child: chat),
              DraggableScrollableSheet(
                initialChildSize: 0.35,
                minChildSize: 0.15,
                maxChildSize: 0.8,
                builder: (context, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: panel,
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  // ---------- 左侧对话区 ----------

  Widget _buildChat(BuildContext context, List<Message> messages) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final isUser = m.role == MessageRole.user;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
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

  // ---------- 右侧上下文面板 ----------

  Widget _buildPanel(BuildContext context, List<Message> messages) {
    final files = _collectFiles(messages);
    final tools = _collectTools(messages);
    final sources = _collectSources(messages);
    final itemCount = files.length + tools.length + sources.length;

    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('上下文（$itemCount 项）',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          // Tab 切换
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: '文件', icon: Icon(Icons.attach_file, size: 16)),
              Tab(text: '工具', icon: Icon(Icons.build_circle, size: 16)),
              Tab(text: '引用', icon: Icon(Icons.format_quote, size: 16)),
              Tab(text: '模型', icon: Icon(Icons.memory, size: 16)),
            ],
            onTap: (i) => updateUIState(uiState.copyWith(
                activeContextPanelTab: ContextPanelTab.values[i])),
          ),
          Expanded(
            child: _buildPanelBody(context, messages, files, tools, sources),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelBody(
    BuildContext context,
    List<Message> messages,
    List<FilePart> files,
    List<ToolCallPart> tools,
    List<Message> sources,
  ) {
    switch (uiState.activeContextPanelTab) {
      case ContextPanelTab.files:
        return _FilesPanel(files: files, onRemove: (id) {
          _removedFileIds.add(id);
          updateUIState(uiState); // 触发重建
        }, onOpen: () {
          showAppSnackBar(context, message: '打开文件（占位）');
        });
      case ContextPanelTab.tools:
        return _ToolsPanel(
          tools: tools,
          uiState: uiState,
          onUIStateChanged: updateUIState,
        );
      case ContextPanelTab.sources:
        return _SourcesPanel(sources: sources);
      case ContextPanelTab.model:
        return _ModelPanel(messages: messages);
    }
  }

  List<FilePart> _collectFiles(List<Message> messages) {
    return messages
        .expand((m) => m.files)
        .where((f) => !_removedFileIds.contains(f.id))
        .toList();
  }

  List<ToolCallPart> _collectTools(List<Message> messages) {
    return messages.expand((m) => m.toolCalls).toList();
  }

  List<Message> _collectSources(List<Message> messages) {
    return messages.where((m) => m.referencedMessageId != null).toList();
  }
}

/// 文件 Tab
class _FilesPanel extends StatelessWidget {
  final List<FilePart> files;
  final void Function(String id) onRemove;
  final VoidCallback onOpen;

  const _FilesPanel({
    required this.files,
    required this.onRemove,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const _EmptyHint(text: '暂无文件');
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: files
          .map((f) => FilePartRenderer(
                part: f,
                onTap: onOpen,
              ))
          .toList(),
    );
  }
}

/// 工具 Tab
class _ToolsPanel extends StatelessWidget {
  final List<ToolCallPart> tools;
  final ConversationUIState uiState;
  final void Function(ConversationUIState) onUIStateChanged;

  const _ToolsPanel({
    required this.tools,
    required this.uiState,
    required this.onUIStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) {
      return const _EmptyHint(text: '暂无工具调用');
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: tools
          .map((t) => ToolCallPartRenderer(
                part: t,
                expanded: uiState.expandedToolCallIds.contains(t.id),
                onToggleExpand: () =>
                    onUIStateChanged(uiState.toggleToolCall(t.id)),
              ))
          .toList(),
    );
  }
}

/// 引用来源 Tab
class _SourcesPanel extends StatelessWidget {
  final List<Message> sources;

  const _SourcesPanel({required this.sources});

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const _EmptyHint(text: '暂无引用来源');
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: sources.map((m) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_quote, size: 14),
                  const SizedBox(width: 4),
                  Text('引用消息 ${m.referencedMessageId}',
                      style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                m.textContent,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 模型 Tab
class _ModelPanel extends StatelessWidget {
  final List<Message> messages;

  const _ModelPanel({required this.messages});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelIds = messages
        .map((m) => m.modelId)
        .whereType<String>()
        .toSet()
        .toList();
    final totalTokens = messages.fold<int>(
        0, (sum, m) => sum + (m.totalTokens ?? 0));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _InfoRow(
          icon: Icons.memory,
          title: '当前模型',
          subtitle: modelIds.isEmpty ? '未知' : modelIds.join(', '),
        ),
        _InfoRow(
          icon: Icons.token,
          title: 'Token 用量',
          subtitle: '$totalTokens tokens',
        ),
        LinearProgressIndicator(value: totalTokens / 100000),
        const SizedBox(height: 8),
        Text('会话消息数：${messages.length}',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 信息行：leading 图标 + 标题 + 副标题（替代裸 ListTile，规避设计系统 lint）。
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态提示
class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
    );
  }
}
