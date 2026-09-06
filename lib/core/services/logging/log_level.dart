/// 日志等级，由低到高。[none] 用作阈值时关闭一切输出。
/// 顺序即严重程度：阈值 [Logger.minLevel] 之下的日志一律跳过。
enum LogLevel {
  verbose,
  debug,
  info,
  warn,
  error,
  none;

  /// 返回大写形式（供落盘格式）。
  String get nameUpper => name.toUpperCase();

  /// 人类可读中文。
  String get zh => switch (this) {
        LogLevel.verbose => '详细',
        LogLevel.debug => '调试',
        LogLevel.info => '信息',
        LogLevel.warn => '警告',
        LogLevel.error => '错误',
        LogLevel.none => '关闭',
      };
}
