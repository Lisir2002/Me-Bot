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

  /// 独占归属优先级：越靠前越优先"认领"文件。
  ///
  /// 「图片」是跨目录总览视图（聚合 images/、upload/、avatars/ 的图片），
  /// 必须排在最后兜底；否则它会先把所有图片认领走，其余分类的独占值全变 0，
  /// 环形图上只剩「图片」一段。
  static const List<String> _exclusivePriority = [
    'chats',
    'upload',
    'snapshots',
    'avatars',
    'logs',
    'cache',
    'other',
    'images',
  ];

  /// 全量扫描。
  static Future<StorageStats> scanAll() async {
    final appData = await AppDirectories.getAppDataDirectory();
    final results = <StorageScan>[];

    results.add(await _scanAllImages(appData));
    results.add(await _scanSubdir(appData, id: 'upload', subdir: 'upload'));
    results.add(await _scanSubdir(appData, id: 'snapshots', subdir: 'snapshots'));
    // 「助手」= 助手自身产生的文件（助手头像 assistant_*、助手生图），
    // 用户头像（avatar_* 前缀）不属于助手，不计入本分类。
    results.add(await _scanSubdir(
      appData,
      id: 'avatars',
      subdir: 'avatars',
      onlySource: 'assistant',
    ));
    results.add(await _scanSubdir(appData, id: 'logs', subdir: 'logs'));
    results.add(await _scanChatDb(appData));
    results.add(await _scanCache(appData));
    results.add(await _scanOther(appData));

    // 计算每个分类的「独占」字节。
    // 同一文件可能同时出现在多个分类视图里（如助手头像既在「图片」总览、
    // 又在「助手」分类），各分类 bytes 相加会超过真实占用。按优先级让
    // 靠前的分类先认领，保证每个文件路径只被计入一次。
    final seen = <String>{};
    final exclusive = <String, int>{};
    for (final id in _exclusivePriority) {
      StorageScan? cat;
      for (final c in results) {
        if (c.id == id) {
          cat = c;
          break;
        }
      }
      if (cat == null) continue;
      var ex = 0;
      for (final e in cat.entries) {
        if (seen.add(e.path)) ex += e.bytes;
      }
      exclusive[id] = ex;
    }
    // 兜底：优先级表未覆盖的分类（防御性，避免漏算）。
    for (final c in results) {
      if (exclusive.containsKey(c.id)) continue;
      var ex = 0;
      for (final e in c.entries) {
        if (seen.add(e.path)) ex += e.bytes;
      }
      exclusive[c.id] = ex;
    }

    final withExclusive = results
        .map(
          (c) => StorageScan(
            id: c.id,
            bytes: c.bytes,
            fileCount: c.fileCount,
            entries: c.entries,
            exclusiveBytes: exclusive[c.id] ?? 0,
          ),
        )
        .toList();

    // 顶层总占用 = 各分类独占值之和（等价于所有去重文件的并集），
    // 与环形图各段之和严格相等。
    final total = exclusive.values.fold(0, (s, v) => s + v);
    final cleanable = withExclusive
        .where((c) => c.id == 'cache' || c.id == 'logs')
        .fold(0, (s, c) => s + c.bytes);

    return StorageStats(
      categories: withExclusive,
      totalBytes: total,
      cleanableBytes: cleanable,
    );
  }

  static Future<StorageScan> _scanSubdir(
    Directory appData, {
    required String id,
    required String subdir,
    // 只收录指定归属方的文件（'user' / 'assistant'），null 表示全部。
    String? onlySource,
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
          final name = _basename(ent.path);
          final src = _sourceOf(name, subdir);
          if (onlySource != null && src != onlySource) continue;
          count += 1;
          try {
            final len = ent.lengthSync();
            bytes += len;
            entries.add(StorageEntry(
              name: name,
              path: ent.path,
              bytes: len,
              modified: ent.statSync().modified,
              source: src,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return StorageScan(id: id, bytes: bytes, fileCount: count, entries: entries);
  }

  /// 判定文件归属方：'user'（用户）或 'assistant'（助手）。
  ///
  /// avatars/ 下同时存放两类头像，靠写入方约定的文件名前缀区分：
  /// - `assistant_<id>_<ts>.<ext>` —— assistant_provider 写入，助手头像
  /// - `avatar_<ts>.<ext>`          —— user_provider 写入，用户头像
  /// 助手生图落盘同样使用 `assistant_` 前缀（见 ChatApiService），
  /// 因此可被识别为助手产物。
  /// 其余目录（upload/、images/ 等）目前只承载用户侧内容。
  static String _sourceOf(String name, String subdir) {
    if (subdir == 'avatars') {
      if (name.toLowerCase().startsWith('assistant_')) return 'assistant';
      return 'user';
    }
    return 'user';
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
              source: _sourceOf(name, sub),
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
  /// 明细列表需要同时包含两处的文件，否则会出现「有大小但明细空」。
  static Future<StorageScan> _scanCache(Directory appData) async {
    final appCache = await _scanSubdir(appData, id: 'cache', subdir: 'cache');
    int sysBytes = 0;
    int sysCount = 0;
    final sysEntries = <StorageEntry>[];
    try {
      final temp = await getTemporaryDirectory();
      await for (final ent in temp.list(recursive: true, followLinks: false)) {
        if (ent is File) {
          sysCount += 1;
          try {
            final len = ent.lengthSync();
            sysBytes += len;
            sysEntries.add(StorageEntry(
              name: _basename(ent.path),
              path: ent.path,
              bytes: len,
              modified: ent.statSync().modified,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return StorageScan(
      id: 'cache',
      bytes: appCache.bytes + sysBytes,
      fileCount: appCache.fileCount + sysCount,
      entries: [...appCache.entries, ...sysEntries],
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