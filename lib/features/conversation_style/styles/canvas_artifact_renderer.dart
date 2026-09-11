// ignore_for_file: hardcoded_ui_string
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/snackbar.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// Style 15: 画布产物渲染器
///
/// 对话 + 画布并排。宽屏 Row（对话 1/2 + 画布 1/2），
/// 窄屏（< 600）改为上下布局。画布按 ArtifactType 渲染文档/代码/
/// 图片/图表/网页占位/表格，支持编辑与预览/代码切换。
class CanvasArtifactRenderer extends BaseStyleRenderer {
  /// 编辑器控制器缓存（artifactId -> controller）
  final Map<String, TextEditingController> _editors = {};

  /// 预览/代码切换（本地 UI 状态）
  bool _isPreview = true;

  @override
  ConversationStyle get style => ConversationStyle.canvasArtifact;

  @override
  void onDetach() {
    for (final c in _editors.values) {
      c.dispose();
    }
    _editors.clear();
    super.onDetach();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        final artifacts = _collectArtifacts(messages);
        final chat = _buildChat(context, messages);
        final canvas = _buildCanvas(context, artifacts);

        return LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 1, child: chat),
                Expanded(flex: 1, child: canvas),
              ],
            );
          }
          // 窄屏：上下布局，对话在上可折叠，画布在下
          return Column(
            children: [
              Expanded(flex: 1, child: chat),
              Expanded(flex: 1, child: canvas),
            ],
          );
        });
      },
    );
  }

  List<ArtifactPart> _collectArtifacts(List<Message> messages) {
    return messages.expand((m) => m.artifacts).toList();
  }

  // ---------- 左侧对话区 ----------

  Widget _buildChat(BuildContext context, List<Message> messages) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: MediaQuery.of(context).size.width >= 600
              ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
              : BorderSide.none,
          bottom: MediaQuery.of(context).size.width < 600
              ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final m = messages[index];
          final isUser = m.role == MessageRole.user;
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6),
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
                children: m.parts.map((p) {
                  if (p is ArtifactPart) {
                    // 产物在对话区仅显示"已在画布中打开"标签
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ArtifactPartRenderer(part: p),
                        Text('已在画布中打开',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    );
                  }
                  return MessagePartRenderer(
                    part: p,
                    uiState: uiState,
                    onUIStateChanged: updateUIState,
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 右侧画布区 ----------

  Widget _buildCanvas(BuildContext context, List<ArtifactPart> artifacts) {
    final theme = Theme.of(context);
    ArtifactPart? active;
    for (final a in artifacts) {
      if (a.artifactId == uiState.activeArtifactTab) {
        active = a;
        break;
      }
    }
    active ??= artifacts.isNotEmpty ? artifacts.first : null;

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // 顶部产物 Tab 栏
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: artifacts.isEmpty
                ? Center(
                    child: Text('画布',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: artifacts.map((a) {
                      final isActive = a.artifactId == active!.artifactId;
                      return InkWell(
                        onTap: () => updateUIState(uiState.copyWith(
                            activeArtifactTab: a.artifactId)),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            a.title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          // 画布内容
          Expanded(
            child: active == null
                ? const _EmptyCanvas()
                : _CanvasBody(
                    artifact: active,
                    isPreview: _isPreview,
                    editors: _editors,
                  ),
          ),
          // 底部工具栏
          if (active != null)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _isPreview = !_isPreview;
                      updateUIState(uiState);
                    },
                    icon: Icon(_isPreview
                        ? Icons.code
                        : Icons.visibility),
                    label: Text(_isPreview ? '代码' : '预览'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => updateUIState(uiState),
                  ),
                  IconButton(
                    tooltip: '下载',
                    icon: const Icon(Icons.download, size: 18),
                    onPressed: () =>
                        showAppSnackBar(context, message: '已下载'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 画布主体：按类型渲染
class _CanvasBody extends StatelessWidget {
  final ArtifactPart artifact;
  final bool isPreview;
  final Map<String, TextEditingController> editors;

  const _CanvasBody({
    required this.artifact,
    required this.isPreview,
    required this.editors,
  });

  @override
  Widget build(BuildContext context) {
    final preview = artifact.preview ?? '';
    switch (artifact.type) {
      case ArtifactType.document:
      case ArtifactType.code:
        final controller = editors.putIfAbsent(
            artifact.artifactId, () => TextEditingController(text: preview));
        if (isPreview) {
          return _DocumentPreview(artifact: artifact);
        }
        return _CodeEditor(artifact: artifact, controller: controller);
      case ArtifactType.image:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image, size: 64, color: Colors.grey),
              const SizedBox(height: 8),
              Text(artifact.title),
            ],
          ),
        );
      case ArtifactType.chart:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: _CanvasBarChart(),
        );
      case ArtifactType.web:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language, size: 64, color: Colors.grey),
              SizedBox(height: 8),
              Text('网页预览'),
            ],
          ),
        );
      case ArtifactType.table:
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('名称')),
              DataColumn(label: Text('数值')),
            ],
            rows: const [
              DataRow(cells: [DataCell(Text('A')), DataCell(Text('12'))]),
              DataRow(cells: [DataCell(Text('B')), DataCell(Text('28'))]),
              DataRow(cells: [DataCell(Text('C')), DataCell(Text('19'))]),
            ],
          ),
        );
    }
  }
}

/// 文档预览
class _DocumentPreview extends StatelessWidget {
  final ArtifactPart artifact;
  const _DocumentPreview({required this.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(artifact.title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(artifact.preview ?? '', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// 代码编辑区：等宽字体 + 行号
class _CodeEditor extends StatelessWidget {
  final ArtifactPart artifact;
  final TextEditingController controller;

  const _CodeEditor({required this.artifact, required this.controller});

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(controller.text).length + 1;
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 行号列
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 1; i <= lines; i++)
                Text('$i',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 12)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: false,
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画布柱状图
class _CanvasBarChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: true)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < 5; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (i * 9 + 11).toDouble(),
                color: theme.colorScheme.primary,
                width: 20,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}

/// 空画布提示
class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('暂无产物',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 4),
          Text('助手生成内容后将显示在这里',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }
}
