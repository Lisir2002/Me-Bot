/// 全项目统一的日志 Tag 常量。
///
/// 每个模块/功能点一个固定 Tag，供日志查看器按来源过滤。
/// 约定：Tag 名用 PascalCase，最多 20 字符，语义清晰。
class LogTags {
  LogTags._();

  // ── App 启动 / 全局 ──
  static const String app = 'App';
  static const String boot = 'Boot';
  static const String lifecycle = 'Lifecycle';
  static const String error = 'Error';

  // ── Provider ──
  static const String storage = 'Storage';
  static const String chat = 'Chat';
  static const String model = 'Model';
  static const String assistant = 'Assistant';
  static const String mcp = 'Mcp';
  static const String backup = 'Backup';
  static const String memory = 'Memory';
  static const String quickPhrase = 'QuickPhrase';
  static const String tag = 'Tag';
  static const String settings = 'Settings';
  static const String tts = 'Tts';
  static const String update = 'Update';
  static const String user = 'User';

  // ── Service ──
  static const String api = 'Api';
  static const String apiReq = 'ApiReq';
  static const String apiRes = 'ApiRes';
  static const String apiErr = 'ApiErr';
  static const String storageService = 'StorageService';
  static const String logStore = 'LogStore';
  static const String logger = 'Logger';
  static const String mcpTool = 'McpTool';
  static const String notification = 'Notification';
  static const String background = 'Background';
  static const String search = 'Search';
  static const String apiKey = 'ApiKey';
  static const String provider = 'Provider';

  // ── Feature ──
  static const String home = 'Home';
  static const String chatInput = 'ChatInput';
  static const String mediaPicker = 'MediaPicker';
  static const String imageViewer = 'ImageViewer';
  static const String translate = 'Translate';
  static const String qr = 'Qr';
  static const String settingsUi = 'SettingsUi';

  // ── Desktop ──
  static const String desktop = 'Desktop';
  static const String window = 'Window';

  // ── Auth ──
  static const String auth = 'Auth';
  static const String token = 'Token';
}
