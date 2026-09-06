import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/backup.dart';
import '../services/chat/chat_service.dart';
import '../services/backup/data_sync.dart';
import '../services/logging/logger.dart';
import '../services/logging/log_tags.dart';

class BackupProvider extends ChangeNotifier {
  final DataSync _dataSync;
  WebDavConfig _cfg;
  bool _busy = false;
  String? _message;

  BackupProvider({required ChatService chatService, WebDavConfig? initialConfig})
      : _dataSync = DataSync(chatService: chatService),
        _cfg = initialConfig ?? const WebDavConfig();

  WebDavConfig get config => _cfg;
  bool get busy => _busy;
  String? get message => _message;

  void updateConfig(WebDavConfig cfg) {
    Logger.d(LogTags.backup, 'updateConfig: ${cfg.url}');
    _cfg = cfg;
    notifyListeners();
  }

  Future<void> test() async {
    Logger.i(LogTags.backup, 'Test WebDAV config: ${_cfg.url}');
    _busy = true; _message = null; notifyListeners();
    final sw = Stopwatch()..start();
    try {
      await _dataSync.testWebdav(_cfg);
      _message = 'OK';
      Logger.i(LogTags.backup, 'Test OK (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      _message = e.toString();
      Logger.e(LogTags.backup, 'Test failed (${sw.elapsedMilliseconds}ms)', e, st);
    } finally {
      _busy = false; notifyListeners();
    }
  }

  Future<void> backup() async {
    Logger.i(LogTags.backup, 'Backup start to ${_cfg.url}');
    _busy = true; _message = null; notifyListeners();
    final sw = Stopwatch()..start();
    try {
      await _dataSync.backupToWebDav(_cfg);
      _message = 'Backup uploaded';
      Logger.i(LogTags.backup, 'Backup done (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      _message = e.toString();
      Logger.e(LogTags.backup, 'Backup failed (${sw.elapsedMilliseconds}ms)', e, st);
    } finally {
      _busy = false; notifyListeners();
    }
  }

  Future<void> restoreFromItem(BackupFileItem item, {RestoreMode mode = RestoreMode.overwrite}) async {
    Logger.w(LogTags.backup, 'Restore from remote: ${item.displayName} mode=$mode');
    _busy = true; _message = null; notifyListeners();
    final sw = Stopwatch()..start();
    try {
      await _dataSync.restoreFromWebDav(_cfg, item, mode: mode);
      _message = 'Restored';
      Logger.i(LogTags.backup, 'Restore done (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      _message = e.toString();
      Logger.e(LogTags.backup, 'Restore failed (${sw.elapsedMilliseconds}ms)', e, st);
    } finally {
      _busy = false; notifyListeners();
    }
  }

  Future<List<BackupFileItem>> listRemote() async {
    Logger.d(LogTags.backup, 'List remote backups from ${_cfg.url}');
    final sw = Stopwatch()..start();
    try {
      final list = await _dataSync.listBackupFiles(_cfg);
      Logger.d(LogTags.backup, 'List remote done: ${list.length} items (${sw.elapsedMilliseconds}ms)');
      return list;
    } catch (e, st) {
      Logger.e(LogTags.backup, 'List remote failed (${sw.elapsedMilliseconds}ms)', e, st);
      rethrow;
    }
  }

  Future<List<BackupFileItem>> deleteAndReload(BackupFileItem item) async {
    Logger.w(LogTags.backup, 'Delete remote backup: ${item.displayName}');
    try {
      await _dataSync.deleteWebDavBackupFile(_cfg, item);
      return _dataSync.listBackupFiles(_cfg);
    } catch (e, st) {
      Logger.e(LogTags.backup, 'Delete failed', e, st);
      rethrow;
    }
  }

  Future<File> exportToFile() async {
    Logger.i(LogTags.backup, 'Export to local file');
    try {
      return await _dataSync.exportToFile(_cfg);
    } catch (e, st) {
      Logger.e(LogTags.backup, 'Export failed', e, st);
      rethrow;
    }
  }

  Future<void> restoreFromLocalFile(File file, {RestoreMode mode = RestoreMode.overwrite}) async {
    Logger.w(LogTags.backup, 'Restore from local: ${file.path} mode=$mode');
    final sw = Stopwatch()..start();
    try {
      await _dataSync.restoreFromLocalFile(file, _cfg, mode: mode);
      Logger.i(LogTags.backup, 'Local restore done (${sw.elapsedMilliseconds}ms)');
    } catch (e, st) {
      Logger.e(LogTags.backup, 'Local restore failed (${sw.elapsedMilliseconds}ms)', e, st);
      rethrow;
    }
  }
}
