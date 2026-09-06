import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../utils/app_directories.dart';
import '../../models/storage.dart';

/// 文件扫描与分类汇总服务。
/// 沿用 ChatService.getUploadStats 的单线程递归模式，避免 isolate 序列化复杂度。
class StorageService {
  StorageService._();

  static const Set<String> _knownSubdirs = {
    'images',
    'upload',
    'snapshots',
    'avatars',
    'cache',
    'logs',
  };

  static const Set<String> _chatDbNames = {
    'conversations.hive',
    'messages.hive',
    'tool_events_v1.hive',
  };

  /// 图片扩展名：凡属这些类型的文件都会聚合进「图片」分类。
  static const Set<String> _imageExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif',
    '.heic', '.heif', '.bmp', '.tiff', '.tif', '.avif',
  };

  /// 是否属于数据库类文件（被「聊天记录」占用）。
  static bool _isDbFile(String name) {
    return _chatDbNames.contains(name) ||
        name.endsWith('.hive') ||
        name.endsWith('.hive.lock') ||
        name.endsWith('.db') ||
        name.endsWith('.db-wal') ||
        name.endsWith('.db-shm') ||
        name.endsWith('.lock');
  }

  /// 全量扫描。
  static Future<StorageStats> scanAll() async {
    final appData = await AppDirectories.getAppDataDirectory();
    final results = <StorageScan>[];

    results.add(await _scanAllImages(appData));
    results.add(await _scanSubdir(appData, id: 'upload', subdir: 'upload'));
    results.add(await _scanSubdir(appData, id: 'snapshots', subdir: 'snapshots'));
    results.add(await _scanSubdir(appData, id: 'avatars', subdir: 'avatars'));
    results.add(await _scanSubdir(appData, id: 'logs', subdir: 'logs'));
    results.add(await _scanChatDb(appData));
    results.add(await _scanCache(appData));
    results.add(await _scanOther(appData));

    final total = results.fold(0, (s, c) => s + c.bytes);
    final cleanable = results
        .where((c) => c.id == 'cache' || c.id == 'logs')
        .fold(0, (s, c) => s + c.bytes);

    return StorageStats(
      categories: results,
      totalBytes: total,
      cleanableBytes: cleanable,
    );
  }

  static Future<StorageScan> _scanSubdir(
    Directory appData, {
    required String id,
    required String subdir,
  }) async {
    final dir = Directory('${appData.path}/$subdir');
    if (!await dir.exists()) {
      return StorageScan(id: id, bytes: 0, fileCount: 0, entries: const []);
    }
    int bytes = 0;
    int count = 0;
    final entries = <StorageEntry>[];
    try {
      await for (final ent in dir.list(recursive: true, followLinks: false)) {
        if (ent is File) {
          count += 1;
          try {
            final len = ent.lengthSync();
            bytes += len;
            entries.add(StorageEntry(
              name: _basename(ent.path),
              path: ent.path,
              bytes: len,
              modified: ent.statSync().modified,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return StorageScan(id: id, bytes: bytes, fileCount: count, entries: entries);
  }

  /// 「图片」分类：聚合 images/、upload/、avatars/ 下的所有图片文件，
  /// 让用户头像、聊天中发送/接收的图片都能在「图片」里看到。
  static Future<StorageScan> _scanAllImages(Directory appData) async {
    int bytes = 0;
    int count = 0;
    final entries = <StorageEntry>[];
    for (final sub in const ['images', 'upload', 'avatars']) {
      final dir = Directory('${appData.path}/$sub');
      if (!await dir.exists()) continue;
      try {
        await for (final ent in dir.list(recursive: true, followLinks: false)) {
          if (ent is! File) continue;
          final name = _basename(ent.path);
          final lower = name.toLowerCase();
          final hasImageExt = _imageExtensions.any(lower.endsWith);
          if (!hasImageExt) continue;
          count += 1;
          try {
            final len = ent.lengthSync();
            bytes += len;
            entries.add(StorageEntry(
              name: name,
              path: ent.path,
              bytes: len,
              modified: ent.statSync().modified,
            ));
          } catch (_) {}
        }
      } catch (_) {}
    }
    return StorageScan(id: 'images', bytes: bytes, fileCount: count, entries: entries);
  }

  /// 聊天记录 = appData 根下的数据库文件。
  static Future<StorageScan> _scanChatDb(Directory appData) async {
    int bytes = 0;
    int count = 0;
    final entries = <StorageEntry>[];
    try {
      for (final ent in appData.listSync(followLinks: false)) {
        if (ent is! File) continue;
        final name = _basename(ent.path);
        if (!_isDbFile(name)) continue;
        count += 1;
        try {
          final len = ent.lengthSync();
          bytes += len;
          entries.add(StorageEntry(
            name: name,
            path: ent.path,
            bytes: len,
            modified: ent.statSync().modified,
          ));
        } catch (_) {}
      }
    } catch (_) {}
    return StorageScan(id: 'chats', bytes: bytes, fileCount: count, entries: entries);
  }

  /// 缓存 = appData/cache + 系统临时目录。
  static Future<StorageScan> _scanCache(Directory appData) async {
    final appCache = await _scanSubdir(appData, id: 'cache', subdir: 'cache');
    int sysBytes = 0;
    int sysCount = 0;
    try {
      final temp = await getTemporaryDirectory();
      await for (final ent in temp.list(recursive: true, followLinks: false)) {
        if (ent is File) {
          sysCount += 1;
          try {
            sysBytes += ent.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return StorageScan(
      id: 'cache',
      bytes: appCache.bytes + sysBytes,
      fileCount: appCache.fileCount + sysCount,
      entries: appCache.entries,
    );
  }

  /// 其他 = appData 根下扣除已知子目录与数据库文件后的剩余。
  static Future<StorageScan> _scanOther(Directory appData) async {
    int bytes = 0;
    int count = 0;
    final entries = <StorageEntry>[];
    try {
      final roots = appData.listSync(followLinks: false);
      for (final root in roots) {
        final name = _basename(root.path);
        if (root is Directory && _knownSubdirs.contains(name)) continue;
        if (root is File && _isDbFile(name)) continue;

        // 收集该根条目下的所有普通文件
        final files = <File>[];
        try {
          if (root is Directory) {
            await for (final f in root.list(recursive: true, followLinks: false)) {
              if (f is File) files.add(f);
            }
          } else if (root is File) {
            files.add(root);
          }
        } catch (_) {}

        for (final f in files) {
          count += 1;
          try {
            final len = f.lengthSync();
            bytes += len;
            entries.add(StorageEntry(
              name: _basename(f.path),
              path: f.path,
              bytes: len,
              modified: f.statSync().modified,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return StorageScan(id: 'other', bytes: bytes, fileCount: count, entries: entries);
  }

  static String _basename(String path) {
    final segs = path.split(Platform.isWindows ? '\\' : '/');
    return segs.isNotEmpty ? segs.last : path;
  }
}