import 'dart:async';
import 'package:flutter/material.dart';
import '../data/conversation_data_source.dart';
import '../models/conversation_style.dart';
import '../models/style_settings.dart';
import 'style_renderer.dart';
import 'style_renderer_registry.dart';

/// 样式切换控制器 —— 处理样式切换和过渡动画
///
/// 职责：
/// 1. 持有当前激活的 StyleRenderer
/// 2. 切换样式时：detach 旧渲染器 → attach 新渲染器
/// 3. 通知数据源样式切换（不改变数据状态）
/// 4. 管理 UI 状态（跨样式共享）
/// 5. 提供切换过渡动画
class StyleSwitcher extends ChangeNotifier {
  final StyleRendererRegistry _registry;
  final ConversationDataSource _dataSource;

  StyleRenderer? _currentRenderer;
  ConversationStyle _currentStyle;
  ConversationUIState _uiState;
  bool _isSwitching = false;

  /// 连续降级计数（连续 3 次降级后锁定为经典气泡）
  final Map<ConversationStyle, int> _fallbackCounts = {};

  /// 被锁定为经典气泡的会话（连续降级后）
  final Set<String> _lockedConversations = {};

  StyleSwitcher({
    required StyleRendererRegistry registry,
    required ConversationDataSource dataSource,
    ConversationStyle initialStyle = ConversationStyle.classicBubble,
    ConversationUIState initialUiState = const ConversationUIState(),
  })  : _registry = registry,
        _dataSource = dataSource,
        _currentStyle = initialStyle,
        _uiState = initialUiState;

  /// 当前样式
  ConversationStyle get currentStyle => _currentStyle;

  /// 当前渲染器
  StyleRenderer? get currentRenderer => _currentRenderer;

  /// 当前 UI 状态
  ConversationUIState get uiState => _uiState;

  /// 是否正在切换
  bool get isSwitching => _isSwitching;

  /// 初始化（attach 初始样式渲染器）
  void initialize() {
    _attachRenderer(_currentStyle);
  }

  /// 切换样式
  Future<void> switchTo(ConversationStyle newStyle) async {
    if (newStyle == _currentStyle || _isSwitching) return;

    // 检查是否被锁定
    if (_lockedConversations.contains(_dataSource.conversationId) &&
        newStyle != ConversationStyle.classicBubble) {
      // 被锁定的会话只能使用经典气泡
      return;
    }

    _isSwitching = true;
    notifyListeners();

    // 通知数据源样式即将切换
    await _dataSource.onStyleWillChange(newStyle);

    // detach 旧渲染器
    _currentRenderer?.onDetach();

    // attach 新渲染器
    _currentStyle = newStyle;
    _attachRenderer(newStyle);

    // 通知数据源样式切换完成
    await _dataSource.onStyleDidChange(newStyle);

    _isSwitching = false;
    notifyListeners();
  }

  void _attachRenderer(ConversationStyle style) {
    if (!_registry.isRegistered(style)) {
      // 回退到经典气泡
      style = ConversationStyle.classicBubble;
      _currentStyle = style;
    }

    final renderer = _registry.get(style);
    renderer.attach(
      _dataSource,
      _uiState,
      _onUIStateChanged,
    );
    _currentRenderer = renderer;
  }

  void _onUIStateChanged(ConversationUIState newState) {
    _uiState = newState;
    notifyListeners();
  }

  /// 记录样式渲染降级（连续 3 次后锁定）
  void recordFallback(ConversationStyle failedStyle) {
    final count = (_fallbackCounts[failedStyle] ?? 0) + 1;
    _fallbackCounts[failedStyle] = count;

    if (count >= 3) {
      _lockedConversations.add(_dataSource.conversationId);
      // 自动切换到经典气泡
      switchTo(ConversationStyle.classicBubble);
    }
  }

  /// 重置降级状态
  void resetFallbackState() {
    _fallbackCounts.clear();
    _lockedConversations.remove(_dataSource.conversationId);
  }

  /// 构建当前样式的 UI
  Widget buildCurrent(BuildContext context) {
    return _currentRenderer?.build(context) ??
        const Center(child: CircularProgressIndicator());
  }

  @override
  void dispose() {
    _currentRenderer?.onDetach();
    super.dispose();
  }
}
