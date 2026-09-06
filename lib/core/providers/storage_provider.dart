import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/storage.dart';
import '../services/storage/storage_service.dart';
import '../services/logging/logger.dart';
import '../services/logging/log_tags.dart';

/// 存储页面的状态容器：承载全量扫描结果与加载状态。
///
/// 实时更新策略：
/// - 监听 App 生命周期，从后台切回前台时自动 refresh（覆盖后台期间
///   其他模块产生的文件变化）。
/// - 支持轮询模式（开启后每隔 [pollInterval] 自动扫盘），由页面在
///   initState 时调用 [startPolling]、dispose 时调用 [stopPolling]。
/// - 删除 / 清理操作调用 [deletePaths] 后内部自动 refresh，确保 UI
///   立即反映。
class StorageProvider extends ChangeNotifier with WidgetsBindingObserver {
  StorageStats? _stats;
  bool _loading = false;
  Object? _error;

  StorageStats? get stats => _stats;
  bool get loading => _loading;
  bool get hasData => _stats != null;
  Object? get error => _error;

  /// 当前是否有扫描结果可用（供存储空间入口展示）。
  bool get initialized => _stats != null;

  // ------- 实时轮询 -------
  Timer? _pollTimer;
  static const Duration _defaultPollInterval = Duration(seconds: 5);
  bool _polling = false;
  bool get polling => _polling;

  /// 开启定时自动扫盘。页面进入时调用一次即可。
  void startPolling({Duration interval = _defaultPollInterval}) {
    if (_polling) return;
    _polling = true;
    WidgetsBinding.instance.addObserver(this);
    Logger.i(LogTags.storage, 'Start polling interval=${interval.inSeconds}s');
    _pollTimer = Timer.periodic(interval, (_) {
      if (_polling) refresh(silent: true);
    });
  }

  /// 停止定时扫盘 + 停止 App 生命周期监听。
  void stopPolling() {
    if (!_polling) return;
    _polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    Logger.i(LogTags.storage, 'Stop polling');
  }

  /// App 从后台切回前台时触发一次静默刷新。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Logger.d(LogTags.storage, 'App resumed, silent refresh');
      refresh(silent: true);
    }
  }

  /// 全量扫盘更新 [stats]。
  ///
  /// [silent] 为 true 时不切换 loading 状态（不显示转圈），适合
  /// 定时轮询或 App resume 这种后台刷新；默认 false 会在扫盘开始/
  /// 结束都 notifyListeners，让 UI 展示 loading 态。
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      Logger.d(LogTags.storage, 'refresh(silent=$silent)');
      final sw = Stopwatch()..start();
      _stats = await StorageService.scanAll();
      sw.stop();
      Logger.d(LogTags.storage, 'refresh done in ${sw.elapsedMilliseconds}ms, ${_stats?.categories.length ?? 0} categories');
      _error = null;
    } catch (e, s) {
      _error = e;
      Logger.e(LogTags.storage, 'refresh failed', e, s);
    } finally {
      if (!silent) _loading = false;
      notifyListeners();
    }
  }

  /// 删除指定路径文件（媒体型多选删除 / 缓存清理），删除后自动刷新。
  Future<bool> deletePaths(List<String> paths) async {
    Logger.w(LogTags.storage, 'deletePaths count=${paths.length}');
    int deleted = 0;
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
          deleted++;
        }
      } catch (e, s) {
        Logger.e(LogTags.storage, 'delete failed path=$path', e, s);
      }
    }
    Logger.w(LogTags.storage, 'deletePaths done: $deleted/${paths.length} removed');
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

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
