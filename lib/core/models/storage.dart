import 'package:flutter/material.dart';

/// 存储分类渲染类型，决定详情页形态。
enum StorageCategoryType {
  /// 媒体型：缩略图网格 + 多选 + 来源/排序筛选 + 删除
  media,

  /// 只读明细型：名称 + 大小 + 路径卡片，不可删除
  readOnlyDetail,

  /// 可清理明细型：子项列表 + 顶部批量清理按钮
  cleanableDetail,

  /// 本地副本：含「管理副本」入口 + 说明卡
  snapshotDetail,
}

/// 媒体型分类的来源筛选取值。
enum StorageSource { all, user, assistant }

/// 单个存储条目。
class StorageEntry {
  final String name;
  final String path;
  final int bytes;
  final DateTime? modified;
  final String source; // 'user' | 'assistant'

  const StorageEntry({
    required this.name,
    required this.path,
    required this.bytes,
    this.modified,
    this.source = 'user',
  });
}

/// 单个分类的纯扫描结果（只含数据，不含 UI 配置）。
class StorageScan {
  final String id;
  final int bytes;
  final int fileCount;
  final List<StorageEntry> entries;

  /// 去重后的「独占」字节数：同一文件可能同时出现在多个分类视图中
  /// （例如助手头像既在「图片」总览里、又在「助手」分类里），直接把各分类
  /// bytes 相加会超过真实总占用、让环形图各段之和超过 100%。
  /// 本字段表示「按归属优先级去重后、真正算在该分类头上的字节」，
  /// 环形图与图例必须用它；分类列表展示的 [bytes] 仍是视图总量。
  final int exclusiveBytes;

  const StorageScan({
    required this.id,
    required this.bytes,
    required this.fileCount,
    required this.entries,
    this.exclusiveBytes = 0,
  });
}

/// 分类的 UI 配置，由 UI 层静态维护。
class StorageCategoryConfig {
  final String id;
  final String title; // 已本地化的标题
  final IconData icon;
  final Color color;
  final StorageCategoryType type;
  final String caution; // 风险提示（已本地化）
  final bool supportSourceFilter; // 媒体型来源筛选
  final bool supportOrderFilter; // 媒体型排序
  final bool supportDelete; // 媒体型多选删除

  const StorageCategoryConfig({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.type,
    required this.caution,
    this.supportSourceFilter = false,
    this.supportOrderFilter = false,
    this.supportDelete = false,
  });
}

/// 全量扫描结果。
class StorageStats {
  final List<StorageScan> categories;
  final int totalBytes;
  final int cleanableBytes; // 可清理 = 缓存 + 日志

  const StorageStats({
    required this.categories,
    required this.totalBytes,
    required this.cleanableBytes,
  });

  int get totalFileCount =>
      categories.fold(0, (sum, c) => sum + c.fileCount);
}