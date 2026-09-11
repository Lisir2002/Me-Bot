import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/snackbar.dart';
import '../framework/style_renderer.dart';
import '../models/conversation_style.dart';
import '../models/message_part.dart';
import '../widgets/shared_message_part_renderers.dart';

/// 生成式 UI 组件类型 —— 根据 TextPart 内容智能识别
enum _GenComponentType {
  /// 普通文本
  plain,

  /// KPI 卡片（数字 + 标签）
  kpi,

  /// Markdown 表格
  table,

  /// 图表
  chart,

  /// 表单
  form,

  /// Diff 对比视图
  diff,
}

/// Style 11: 生成式 UI 渲染器
///
/// 设计理念：模型返回交互式组件而非纯文本。
/// 普通文本用 TextPartRenderer，检测到"结构化内容"时渲染为交互式组件
/// （KPI 卡片 / 数据表格 / 图表 / 表单 / Diff 视图）。
class GenerativeUiRenderer extends BaseStyleRenderer {
  /// 表单编辑器控制器缓存（componentId -> controller），onDetach 统一释放
  final Map<String, TextEditingController> _formControllers = {};

  @override
  ConversationStyle get style => ConversationStyle.generativeUi;

  @override
  void onDetach() {
    for (final c in _formControllers.values) {
      c.dispose();
    }
    _formControllers.clear();
    super.onDetach();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: dataSource.messageStream,
      initialData: dataSource.currentMessages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) =>
              _buildMessage(context, messages[index]),
        );
      },
    );
  }

  Widget _buildMessage(BuildContext context, Message message) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: message.parts
              .map((part) => _buildPart(context, message, part))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPart(BuildContext context, Message message, MessagePart part) {
    // TextPart 做结构化内容识别，其余 part 走共享渲染器
    if (part is TextPart) {
      final type = _detectComponentType(part.text);
      switch (type) {
        case _GenComponentType.kpi:
          return _KpiCard(
            key: ValueKey('kpi_${part.id}'),
            part: part,
            expanded: _genState(part.id, 'expanded') == true,
            onTap: () => _toggleGenState(part.id, 'expanded'),
          );
        case _GenComponentType.table:
          return _StructuredTable(
            key: ValueKey('table_${part.id}'),
            part: part,
            sortColumn: _genState(part.id, 'col') as int? ?? 0,
            sortAsc: _genState(part.id, 'asc') as bool? ?? true,
            onSort: (col, asc) => _setGenState(
                part.id, {'col': col, 'asc': asc}),
          );
        case _GenComponentType.chart:
          return _GenChart(part: part);
        case _GenComponentType.form:
          return _GenForm(
            part: part,
            controllers: _formControllers,
            onSubmit: () => showAppSnackBar(context, message: '表单已提交'),
          );
        case _GenComponentType.diff:
          return _DiffView(part: part);
        case _GenComponentType.plain:
          return TextPartRenderer(part: part);
      }
    }
    // 其余 part 类型统一走共享调度器
    return MessagePartRenderer(
      part: part,
      uiState: uiState,
      onUIStateChanged: updateUIState,
    );
  }

  // ---------- 内容识别逻辑 ----------

  _GenComponentType _detectComponentType(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return _GenComponentType.plain;

    // 前缀识别
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('图表:') || lower.startsWith('chart:')) {
      return _GenComponentType.chart;
    }
    if (lower.startsWith('表单:') || lower.startsWith('form:')) {
      return _GenComponentType.form;
    }
    if (lower.startsWith('diff:')) {
      return _GenComponentType.diff;
    }

    // Markdown 表格：至少两行且含 |，且第二行是分隔行
    final lines = trimmed.split('\n').map((l) => l.trim()).toList();
    if (lines.length >= 2 &&
        lines.every((l) => l.contains('|')) &&
        RegExp(r'^\|?\s*:?-{2,}').hasMatch(lines[1])) {
      return _GenComponentType.table;
    }

    // KPI：每行都是 "标签: 数字" 形式
    final kpiLines = lines
        .where((l) =>
            RegExp(r'^[^:：]+[:：]\s*[\d.,]+\s*[万千亿kK%]?.*$').hasMatch(l))
        .toList();
    if (kpiLines.isNotEmpty && kpiLines.length == lines.length) {
      return _GenComponentType.kpi;
    }
    return _GenComponentType.plain;
  }

  // ---------- uiState.generativeUiStates 读写 ----------

  Map<String, dynamic>? _genStateMap(String componentId) =>
      uiState.generativeUiStates[componentId];

  Object? _genState(String componentId, String key) =>
      _genStateMap(componentId)?[key];

  void _toggleGenState(String componentId, String key) {
    final map =
        Map<String, Map<String, dynamic>>.from(uiState.generativeUiStates);
    final inner = Map<String, dynamic>.from(map[componentId] ?? {});
    inner[key] = !(inner[key] == true);
    map[componentId] = inner;
    updateUIState(uiState.copyWith(generativeUiStates: map));
  }

  void _setGenState(String componentId, Map<String, dynamic> values) {
    final map =
        Map<String, Map<String, dynamic>>.from(uiState.generativeUiStates);
    final inner = Map<String, dynamic>.from(map[componentId] ?? {});
    inner.addAll(values);
    map[componentId] = inner;
    updateUIState(uiState.copyWith(generativeUiStates: map));
  }
}

/// KPI 卡片：检测 "标签: 数字" 行，渲染带趋势箭头的卡片
class _KpiCard extends StatelessWidget {
  final TextPart part;
  final bool expanded;
  final VoidCallback onTap;

  const _KpiCard({
    super.key,
    required this.part,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = part.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      final idx = l.indexOf(RegExp(r'[:：]'));
      if (idx < 0) return MapEntry(l, '');
      return MapEntry(l.substring(0, idx).trim(), l.substring(idx + 1).trim());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: entries.map((e) {
            final isUp = e.value.contains('↑') || e.value.contains('+');
            final isDown = e.value.contains('↓') ||
                RegExp(r'-\d').hasMatch(e.value);
            final trendColor = isUp
                ? Colors.green
                : isDown
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant;
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.insights,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(e.key,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            e.value,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          isUp
                              ? Icons.trending_up
                              : isDown
                                  ? Icons.trending_down
                                  : Icons.trending_flat,
                          size: 16,
                          color: trendColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('详情：点击卡片查看更多分析（示例展开区）',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// 可排序数据表格：解析 Markdown 表格行
class _StructuredTable extends StatelessWidget {
  final TextPart part;
  final int sortColumn;
  final bool sortAsc;
  final void Function(int col, bool asc) onSort;

  const _StructuredTable({
    super.key,
    required this.part,
    required this.sortColumn,
    required this.sortAsc,
    required this.onSort,
  });

  List<List<String>> _parseRows() {
    return part.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.contains('|'))
        .map((l) {
      var line = l;
      if (line.startsWith('|')) line = line.substring(1);
      if (line.endsWith('|')) line = line.substring(0, line.length - 1);
      return line.split('|').map((c) => c.trim()).toList();
    }).where((row) => !RegExp(r'^:?-+:?$').hasMatch(row.first))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _parseRows();
    if (rows.isEmpty) return TextPartRenderer(part: part);
    final header = rows.first;
    final data = rows.sublist(1);

    // 排序
    final sorted = List.of(data);
    sorted.sort((a, b) {
      if (sortColumn >= a.length || sortColumn >= b.length) return 0;
      final cmp = num.tryParse(a[sortColumn].replaceAll(RegExp(r'[^\d.]'), ''))
              ?.compareTo(num.tryParse(b[sortColumn].replaceAll(RegExp(r'[^\d.]'), '')) ?? 0) ??
          a[sortColumn].compareTo(b[sortColumn]);
      return sortAsc ? cmp : -cmp;
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        sortColumnIndex: sortColumn,
        sortAscending: sortAsc,
        columns: header
            .map((h) => DataColumn(
                  label: Text(h),
                  onSort: (col, asc) => onSort(col, asc),
                ))
            .toList(),
        rows: sorted
            .map((row) => DataRow(
                cells: row
                    .map((cell) => DataCell(Text(cell)))
                    .toList()))
            .toList(),
      ),
    );
  }
}

/// 图表组件：解析 "图表: 标签: 值" 形式数据，渲染柱状图
class _GenChart extends StatelessWidget {
  final TextPart part;

  const _GenChart({required this.part});

  List<MapEntry<String, double>> _parseData() {
    final lines = part.text.split('\n').skip(1); // 跳过 "图表:" 首行
    final result = <MapEntry<String, double>>[];
    for (final line in lines) {
      final m = RegExp(r'([^:：,，\d]+)[:：]\s*([\d.]+)').firstMatch(line);
      if (m != null) {
        result.add(MapEntry(m.group(1)!.trim(), double.tryParse(m.group(2)!) ?? 0));
      }
    }
    if (result.isEmpty) {
      // 退化：用伪数据
      for (var i = 0; i < 5; i++) {
        result.add(MapEntry('v$i', (i * 7 + 13).toDouble()));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _parseData();
    return Container(
      height: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(data[i].key,
                        style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: data[i].value,
                  color: theme.colorScheme.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// 表单组件：解析 "表单:" 后的字段名，渲染输入框 + 提交按钮
class _GenForm extends StatelessWidget {
  final TextPart part;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onSubmit;

  const _GenForm({
    required this.part,
    required this.controllers,
    required this.onSubmit,
  });

  List<String> _parseFields() {
    return part.text
        .split('\n')
        .skip(1)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .map((l) => l.replaceFirst(RegExp(r'^[-*\d.\s]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = _parseFields();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('交互式表单',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            ...fields.map((f) {
              final controller = controllers.putIfAbsent(
                  '${part.id}_$f', () => TextEditingController());
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: f,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('提交'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diff 视图：以 +/- 前缀区分添加/删除行
class _DiffView extends StatelessWidget {
  final TextPart part;

  const _DiffView({required this.part});

  @override
  Widget build(BuildContext context) {
    final lines = part.text.split('\n').skip(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final isAdd = line.startsWith('+');
          final isDel = line.startsWith('-');
          final color = isAdd
              ? const Color(0xFF7EE787)
              : isDel
                  ? const Color(0xFFF85149)
                  : Colors.white70;
          return Text(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.5,
            ),
          );
        }).toList(),
      ),
    );
  }
}
