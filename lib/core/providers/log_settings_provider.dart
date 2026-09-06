import 'package:flutter/foundation.dart';

import '../../services/logging/logger.dart';
import '../../services/logging/log_level.dart';
import '../../services/logging/log_parser.dart';
import '../../services/logging/log_repository.dart';

/// 日志设置 + 过滤偏好。
///
/// 负责：
/// 1. 读写 Logger.minLevel（落盘最低记录等级）
/// 2. 管理 UI 层的默认过滤偏好（等级 / Tag / 日期范围）
/// 3. 提供统计信息
///
/// 持久化策略：
/// 暂时用 debugPrint 记录设置变更；等项目的 KV store 就绪后接入。
class LogSettingsProvider extends ChangeNotifier {
  LogSettingsProvider() {
    // 同步 Logger 当前等级（Logger.init 在 main 中先完成）
    _minLevel = Logger.minLevel;
  }

  LogLevel _minLevel = LogLevel.verbose;
  LogLevel get minLevel => _minLevel;

  /// 低于 [level] 的日志一律不落盘、也不镜像到控制台。
  void setMinLevel(LogLevel level) {
    if (_minLevel == level) return;
    _minLevel = level;
    Logger.minLevel = level;
    Logger.d('LogSettings', '日志最低等级切换为 ${level.nameUpper} (${level.zh})');
    notifyListeners();
  }

  Set<LogLevel> _selectedLevels = const {};
  Set<LogLevel> get selectedLevels => _selectedLevels;

  Set<String> _selectedTags = const {};
  Set<String> get selectedTags => _selectedTags;

  String _keyword = '';
  String get keyword => _keyword;

  DateTime? _from;
  DateTime? _to;
  DateTime? get from => _from;
  DateTime? get to => _to;

  void setSelectedLevels(Set<LogLevel> v) {
    _selectedLevels = v;
    notifyListeners();
  }

  void setSelectedTags(Set<String> v) {
    _selectedTags = v;
    notifyListeners();
  }

  void setKeyword(String v) {
    _keyword = v;
    notifyListeners();
  }

  void setDateRange({DateTime? from, DateTime? to}) {
    _from = from;
    _to = to;
    notifyListeners();
  }

  void clearFilters() {
    _selectedLevels = const {};
    _selectedTags = const {};
    _keyword = '';
    _from = null;
    _to = null;
    notifyListeners();
  }

  Future<List<ParsedLogLine>> query({int? limit}) async {
    return LogRepository.instance.query(
      levels: _selectedLevels,
      tags: _selectedTags,
      from: _from,
      to: _to,
      keyword: _keyword,
      limit: limit,
    );
  }

  Future<Map<LogLevel, int>> loadLevelStats() async {
    return LogRepository.instance.countByLevel();
  }

  Future<Map<String, int>> loadTagStats() async {
    return LogRepository.instance.countByTag();
  }

  Future<List<String>> loadAllTags() async {
    return LogRepository.instance.allTags();
  }

  Future<int> totalBytes() async => LogRepository.instance.totalBytes();
}
