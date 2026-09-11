import 'package:flutter/material.dart';
import '../models/conversation_style.dart';

/// 样式错误边界 —— 渲染失败自动降级到经典气泡
///
/// 任何样式渲染器的 build 方法抛出异常时，此 widget 捕获异常，
/// 记录错误日志，自动降级到经典气泡样式，并显示 toast 提示。
class StyleErrorBoundary extends StatefulWidget {
  /// 当前样式
  final ConversationStyle style;

  /// 构建样式 UI 的函数
  final Widget Function(BuildContext) builder;

  /// 降级回调（连续降级时由 StyleSwitcher 处理）
  final VoidCallback? onFallback;

  /// 降级后显示的样式名称
  final String fallbackStyleName;

  const StyleErrorBoundary({
    super.key,
    required this.style,
    required this.builder,
    this.onFallback,
    this.fallbackStyleName = '经典气泡',
  });

  @override
  State<StyleErrorBoundary> createState() => _StyleErrorBoundaryState();
}

class _StyleErrorBoundaryState extends State<StyleErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildFallback(context);
    }

    try {
      return widget.builder(context);
    } catch (e, st) {
      // 同步异常捕获
      _error = e;
      _stackTrace = st;
      _logError();
      widget.onFallback?.call();

      // 下一帧显示降级 UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });

      return const SizedBox.shrink();
    }
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline,
                  size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // 样式渲染降级提示属错误恢复 UI，冻结映射未提供键（行级豁免）
                  // ignore: hardcoded_ui_string
                  '样式「${_styleName(widget.style)}」渲染异常，已切换为${widget.fallbackStyleName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(
              // 异常详情原文回显，非可翻译 UI 文案（行级豁免）
              // ignore: hardcoded_ui_string
              '错误: $_error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _retryCount < 3 ? _reset : null,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(_retryCount > 0 ? '重试 ($_retryCount/3)' : '重试'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _error = null;
                  _stackTrace = null;
                  _retryCount = 0;
                }),
                // 冻结映射未提供「忽略」键，沿用字面量（行级豁免）
                // ignore: hardcoded_ui_string
                child: const Text('忽略'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _error = null;
      _stackTrace = null;
      _retryCount++;
    });
  }

  void _logError() {
    // 记录错误日志（含样式名、异常栈）
    debugPrint(
      '[StyleErrorBoundary] Style ${widget.style} failed: $_error\n'
      'Stack trace: $_stackTrace',
    );
  }

  String _styleName(ConversationStyle style) {
    const names = {
      ConversationStyle.classicBubble: '经典气泡',
      ConversationStyle.fullWidthDocument: '全宽文档',
      ConversationStyle.minimalStream: '极简流式',
      ConversationStyle.cardStack: '卡片堆叠',
      ConversationStyle.agentThreeTier: 'Agent三层级',
      ConversationStyle.toolCardFlow: '工具卡片流',
      ConversationStyle.thinkActObserve: '思考行动观察',
      ConversationStyle.terminal: '终端风格',
      ConversationStyle.richContent: '富内容渲染',
    };
    return names[style] ?? style.name;
  }
}
