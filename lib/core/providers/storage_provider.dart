import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/storage.dart';
import '../services/storage/storage_service.dart';

/// 存储页面的状态容器：承载全量扫描结果与加载状态。
class StorageProvider extends ChangeNotifier {
  StorageStats? _stats;
  bool _loading = false;
  Object? _error;

  StorageStats? get stats => _stats;
  bool get loading => _loading;
  bool get hasData => _stats != null;
  Object? get error => _error;

  /// 当前是否有扫描结果可用（供存储空间入口展示）。
  bool get initialized => _stats != null;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _stats = await StorageService.scanAll();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 删除指定路径文件（媒体型多选删除 / 缓存清理），删除后自动刷新。
  Future<bool> deletePaths(List<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await refresh();
    return true;
  }

  StorageScan? scanFor(String id) {
    final stats = _stats;
    if (stats == null) return null;
    for (final c in stats.categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}