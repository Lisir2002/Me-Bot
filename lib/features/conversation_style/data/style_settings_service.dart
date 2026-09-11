import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../framework/style_resolver.dart';
import '../models/conversation_style.dart';
import '../models/style_settings.dart';

/// 样式设置持久化服务 —— 将 [StyleSettings] 写入 Hive
///
/// 存储结构（单 box `style_settings`，单 key 存整份 JSON）：
/// - 全局默认样式 [StyleSettings.globalStyle]
/// - per-assistant 覆盖 [StyleSettings.assistantOverrides]
/// - per-conversation 覆盖 [StyleSettings.conversationOverrides]
/// - autoMode 开关 [StyleSettings.autoModeEnabled]
/// - intentWeights 自动模式意图权重
///
/// 作为 ChangeNotifier，设置变更后通知监听者（设置页 / 对话页）重建。
/// 只读写自己的 box，不接触消息数据（消息走 HiveConversationDataSource）。
class StyleSettingsService extends ChangeNotifier {
  static const String _boxName = 'style_settings';
  static const String _storageKey = 'settings';
  static const String _statsKey = 'usage_stats';

  Box? _box;
  StyleSettings _settings = const StyleSettings();
  StyleUsageStats _usageStats = const StyleUsageStats();
  bool _loaded = false;

  /// 当前设置（未加载时返回默认值）
  StyleSettings get settings => _settings;

  /// 用户行为统计（用于智能推荐）
  StyleUsageStats get usageStats => _usageStats;

  /// 是否已从磁盘加载
  bool get isLoaded => _loaded;

  /// 惰性获取 box：Hive 由 ChatService.init() 统一初始化后再打开
  Future<Box> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box(_boxName);
    } else {
      _box = await Hive.openBox(_boxName);
    }
    return _box!;
  }

  /// 从 Hive 加载设置（应用启动时调用一次）
  Future<void> load() async {
    try {
      final box = await _ensureBox();
      final raw = box.get(_storageKey);
      if (raw is String && raw.trim().isNotEmpty) {
        _settings = StyleSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      final rawStats = box.get(_statsKey);
      if (rawStats is String && rawStats.trim().isNotEmpty) {
        _usageStats = StyleUsageStats.fromJson(
          jsonDecode(rawStats) as Map<String, dynamic>,
        );
      }
    } catch (e, st) {
      // 读取失败时静默回落默认设置，不阻塞启动
      debugPrint('[StyleSettings] load failed: $e\n$st');
      _settings = const StyleSettings();
      _usageStats = const StyleUsageStats();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// 持久化当前设置到 Hive
  Future<void> save() async {
    try {
      final box = await _ensureBox();
      await box.put(_storageKey, jsonEncode(_settings.toJson()));
      await box.put(_statsKey, jsonEncode(_usageStats.toJson()));
    } catch (e, st) {
      debugPrint('[StyleSettings] save failed: $e\n$st');
    }
  }

  /// 记录一次用户切换：from→to 说明 from 不够贴合，降 from 升 to
  Future<void> recordSwitch(
    ConversationStyle from,
    ConversationStyle to,
  ) async {
    _usageStats.recordAway(from);
    _usageStats.recordSelect(to);
    notifyListeners();
    await save();
  }

  /// 记录某样式一段使用时长
  Future<void> recordUsage(ConversationStyle style, double seconds) async {
    _usageStats.addDuration(style, seconds);
    await save();
  }

  /// 清空学习数据
  Future<void> resetUsageStats() async {
    _usageStats = const StyleUsageStats();
    notifyListeners();
    await save();
  }

  /// 应用新设置并持久化
  Future<void> _apply(StyleSettings next) async {
    _settings = next;
    notifyListeners();
    await save();
  }

  /// 设置全局默认样式
  Future<void> setGlobalStyle(ConversationStyle style) =>
      _apply(_settings.copyWith(globalStyle: style));

  /// 设置某助手的样式覆盖（传 null 清除覆盖）
  Future<void> setAssistantOverride(
    String assistantId,
    ConversationStyle? style,
  ) async {
    final next = Map<String, ConversationStyle>.from(_settings.assistantOverrides);
    if (style == null) {
      next.remove(assistantId);
    } else {
      next[assistantId] = style;
    }
    await _apply(_settings.copyWith(assistantOverrides: next));
  }

  /// 设置某会话的样式覆盖（传 null 清除覆盖）
  Future<void> setConversationOverride(
    String conversationId,
    ConversationStyle? style,
  ) async {
    final next =
        Map<String, ConversationStyle>.from(_settings.conversationOverrides);
    if (style == null) {
      next.remove(conversationId);
    } else {
      next[conversationId] = style;
    }
    await _apply(_settings.copyWith(conversationOverrides: next));
  }

  /// 开关自动模式
  Future<void> setAutoMode(bool enabled) =>
      _apply(_settings.copyWith(autoModeEnabled: enabled));

  /// 设置自动模式意图权重
  Future<void> setIntentWeights(Map<String, double> weights) =>
      _apply(_settings.copyWith(intentWeights: weights));

  /// 设置样式切换动画开关
  Future<void> setTransitionAnimation(bool enabled) =>
      _apply(_settings.copyWith(transitionAnimationEnabled: enabled));

  /// 解析当前应生效的样式：会话覆盖 > 助手覆盖 > 全局默认 > 经典气泡
  ///
  /// auto 由 StyleResolver 负责解析；这里只做显式覆盖的优先级回落。
  ConversationStyle resolve({
    String? conversationId,
    String? assistantId,
  }) {
    if (conversationId != null &&
        _settings.conversationOverrides.containsKey(conversationId)) {
      return _settings.conversationOverrides[conversationId]!;
    }
    if (assistantId != null &&
        _settings.assistantOverrides.containsKey(assistantId)) {
      return _settings.assistantOverrides[assistantId]!;
    }
    return _settings.globalStyle;
  }
}
