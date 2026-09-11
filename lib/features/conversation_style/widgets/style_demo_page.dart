import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../conversation_style.dart';

/// 对话流样式演示页面
///
/// 展示所有 15 种样式对同一份 Golden 测试数据的渲染效果。
/// 用户可以在样式之间切换，观察不同样式的视觉差异。
class ConversationStyleDemoPage extends StatefulWidget {
  const ConversationStyleDemoPage({super.key});

  @override
  State<ConversationStyleDemoPage> createState() =>
      _ConversationStyleDemoPageState();
}

class _ConversationStyleDemoPageState extends State<ConversationStyleDemoPage> {
  late final StyleRendererRegistry _registry;
  late final HiveConversationDataSource _dataSource;
  late final StyleSwitcher _switcher;
  ConversationStyle _currentStyle = ConversationStyle.classicBubble;
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();
    _registry = StyleRendererRegistry();
    registerAllStyles(_registry);
    _dataSource = HiveConversationDataSource(conversationId: 'demo');
    _switcher = StyleSwitcher(
      registry: _registry,
      dataSource: _dataSource,
      initialStyle: _currentStyle,
    );
    _switcher.initialize();
    _switcher.addListener(_onSwitcherChanged);
    _loadGoldenData();
  }

  Future<void> _loadGoldenData() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'test/fixtures/conversation_style_golden.json',
      );
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final messagesJson = data['messages'] as List;
      for (final msgJson in messagesJson) {
        final msg = Message.fromJson(msgJson as Map<String, dynamic>);
        _dataSource.upsertMessage(msg);
      }
      if (mounted) {
        setState(() => _dataLoaded = true);
      }
    } catch (e) {
      // 如果加载失败，使用内置示例数据
      _loadSampleData();
    }
  }

  void _loadSampleData() {
    final sampleMessages = [
      Message(
        role: MessageRole.user,
        parts: [TextPart(text: '你好，请帮我分析一下数据。')],
      ),
      Message(
        role: MessageRole.assistant,
        parts: [
          ThinkingPart(content: '用户需要数据分析，我先调用工具。'),
          ToolCallPart(
            toolName: 'data_analysis',
            arguments: {'query': 'sales trends'},
            status: ToolCallStatus.success,
            duration: const Duration(seconds: 2),
          ),
          TextPart(text: '分析完成！营收同比增长23%。'),
          CodePart(code: 'print("Hello")', language: 'python'),
        ],
      ),
    ];
    for (final msg in sampleMessages) {
      _dataSource.upsertMessage(msg);
    }
    if (mounted) {
      setState(() => _dataLoaded = true);
    }
  }

  void _onSwitcherChanged() {
    if (mounted) {
      setState(() {
        _currentStyle = _switcher.currentStyle;
      });
    }
  }

  @override
  void dispose() {
    _switcher.removeListener(_onSwitcherChanged);
    _switcher.dispose();
    _dataSource.dispose();
    super.dispose();
  }

  void _switchStyle(ConversationStyle style) {
    _switcher.switchTo(style);
  }

  @override
  Widget build(BuildContext context) {
    final meta = StyleMetaRegistry.get(_currentStyle);

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话流样式演示'),
        actions: [
          StyleSwitcherButton(
            currentStyle: _currentStyle,
            onStyleSelected: _switchStyle,
          ),
        ],
      ),
      body: Column(
        children: [
          // 样式信息栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    meta.number,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  meta.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    meta.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '信息密度: ${meta.infoDensity}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 样式快速切换栏
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: StyleMetaRegistry.concreteStyles.length,
              itemBuilder: (context, index) {
                final styleMeta = StyleMetaRegistry.concreteStyles[index];
                final isSelected = styleMeta.style == _currentStyle;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text('${styleMeta.number} ${styleMeta.displayName}'),
                    selected: isSelected,
                    onSelected: (_) => _switchStyle(styleMeta.style),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // 样式渲染区域
          Expanded(
            child: !_dataLoaded
                ? const Center(child: CircularProgressIndicator())
                : StyleErrorBoundary(
                    style: _currentStyle,
                    onFallback: () => _switcher.recordFallback(_currentStyle),
                    builder: (context) => _switcher.buildCurrent(context),
                  ),
          ),
        ],
      ),
    );
  }
}
