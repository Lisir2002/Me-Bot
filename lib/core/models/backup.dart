import 'dart:convert';

enum RestoreMode {
  overwrite, // 完全覆盖：清空本地后恢复
  merge,     // 增量合并：智能去重
}

class WebDavConfig {
  final String url;
  final String username;
  final String password;
  final String path;
  final bool includeChats; // Hive boxes
  final bool includeFiles; // uploads/
  final bool keepLocalCopy; // 保留本地副本

  const WebDavConfig({
    this.url = '',
    this.username = '',
    this.password = '',
    this.path = 'minime-core_backups',
    this.includeChats = true,
    this.includeFiles = true,
    this.keepLocalCopy = true,
  });

  WebDavConfig copyWith({
    String? url,
    String? username,
    String? password,
    String? path,
    bool? includeChats,
    bool? includeFiles,
    bool? keepLocalCopy,
  }) {
    return WebDavConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      includeChats: includeChats ?? this.includeChats,
      includeFiles: includeFiles ?? this.includeFiles,
      keepLocalCopy: keepLocalCopy ?? this.keepLocalCopy,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'path': path,
        'includeChats': includeChats,
        'includeFiles': includeFiles,
        'keepLocalCopy': keepLocalCopy,
      };

  static WebDavConfig fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      url: (json['url'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim() ?? '',
      password: (json['password'] as String?) ?? '',
      path: (json['path'] as String?)?.trim().isNotEmpty == true
          ? (json['path'] as String).trim()
          : 'minime-core_backups',
      includeChats: json['includeChats'] as bool? ?? true,
      includeFiles: json['includeFiles'] as bool? ?? true,
      keepLocalCopy: json['keepLocalCopy'] as bool? ?? true,
    );
  }

  static WebDavConfig fromJsonString(String s) {
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return WebDavConfig.fromJson(map);
    } catch (_) {
      return const WebDavConfig();
    }
  }

  String toJsonString() => jsonEncode(toJson());
}

class BackupFileItem {
  final Uri href; // absolute
  final String displayName;
  final int size;
  final DateTime? lastModified;
  const BackupFileItem({
    required this.href,
    required this.displayName,
    required this.size,
    required this.lastModified,
  });
}

