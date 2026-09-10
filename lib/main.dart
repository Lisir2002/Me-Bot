import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
// import 'dart:async';
import 'l10n/app_localizations.dart';
import 'l10n/build_context_l10n.dart';
import 'features/home/pages/home_page.dart';
import 'desktop/desktop_home_page.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop/desktop_window_controller.dart';
// import 'package:logging/logging.dart' as logging;
// Theme is now managed in SettingsProvider
import 'theme/theme_factory.dart';
import 'theme/palettes.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/tts_provider.dart';
import 'core/providers/assistant_provider.dart';
import 'core/providers/tag_provider.dart';
import 'core/providers/update_provider.dart';
import 'core/providers/quick_phrase_provider.dart';
import 'core/providers/memory_provider.dart';
import 'core/providers/backup_provider.dart';
import 'core/providers/storage_provider.dart';
import 'core/services/logging/logger.dart';
import 'core/services/logging/log_tags.dart';
import 'core/providers/log_settings_provider.dart';
import 'core/services/chat/chat_service.dart';
import 'core/services/mcp/mcp_tool_service.dart';
import 'utils/sandbox_path_resolver.dart';
import 'shared/widgets/snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:system_fonts/system_fonts.dart';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/android_background.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_storage/secure_storage_bootstrap.dart';
import 'core/services/migration/migration_context.dart';
import 'core/services/migration/migration_runner.dart';
import 'core/services/migration/steps/credential_migration_v1_step.dart';
import 'core/services/migration/steps/credential_migration_v2_step.dart';

final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();
bool _didCheckUpdates = false; // one-time update check flag
bool _didEnsureAssistants = false; // ensure defaults after l10n ready


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop (Windows) window setup: hide native title bar for custom Flutter bar
  await _initDesktopWindow();
  // Preload system fonts on desktop so saved font selections render on launch
  await _preloadDesktopSystemFonts();
  // Cache current Documents directory to fix sandboxed absolute paths on iOS
  await SandboxPathResolver.init();
  await Logger.init();
  Logger.i(LogTags.boot, 'App boot complete, ready to run');

  // ── 安全存储 + 数据迁移：必须早于任何 provider 构造 ──
  await _initSecureStorage();
  await _runMigrations();

  // ── 全局错误处理：所有未捕获异常落盘到 Logger ──
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    Logger.e(LogTags.error, 'FlutterError: ${details.exception}', details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Logger.e(LogTags.error, 'Platform error: $error', error, stack);
    return true;
  };
  // Count app launches (feeds the Stats page "app launch" card)
  await _incrementAppLaunchCount();
  // Enable edge-to-edge to allow content under system bars (Android)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Start app (no extra guarded zone logging)
runApp(const MyApp());
}

/// 初始化安全存储。失败不阻塞启动：后续 provider 会检测到未初始化并退回明文路径。
Future<void> _initSecureStorage() async {
  try {
    await SecureStorage.init(
      onError: (message, error, stack) =>
          Logger.w(LogTags.storage, message, error, stack),
    );
  } catch (e, s) {
    Logger.e(LogTags.storage, 'secure storage init failed', e, s);
  }
}

/// 执行已注册的迁移步骤。
///
/// 整体 try/catch：迁移属于「尽力而为」，任何失败都不得阻塞启动——
/// 未迁移成功的明文会在下次启动时重试。
Future<void> _runMigrations() async {
  try {
    if (!SecureStorage.isInitialized) {
      Logger.w(LogTags.storage, 'skip migrations: secure storage unavailable');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final runner = MigrationRunner()
      ..register(CredentialMigrationV1Step())
      ..register(CredentialMigrationV2Step());
    final report = await runner.run(
      MigrationContext(
        prefs: prefs,
        secureStorage: SecureStorage.instance,
        log: (level, message, [error, stack]) {
          switch (level) {
            case 'e':
              Logger.e(LogTags.storage, message, error, stack);
            case 'w':
              Logger.w(LogTags.storage, message, error, stack);
            default:
              Logger.i(LogTags.storage, message);
          }
        },
      ),
    );
    Logger.i(LogTags.boot, 'migrations done: $report');
  } catch (e, s) {
    Logger.e(LogTags.boot, 'migration runner crashed', e, s);
  }
}

/// Increments the persistent app-launch counter used by the Stats page.
Future<void> _incrementAppLaunchCount() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const key = 'app_launch_count';
    final prev = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, prev + 1);
  } catch (_) {
    // Best-effort; never block startup on a stats counter.
  }
}

Future<void> _initDesktopWindow() async {
  if (kIsWeb) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    // Initialize and show desktop window with persisted size/position
    await DesktopWindowController.instance.initializeAndShow(title: 'MiniMe-Core');
  } catch (_) {
    // Ignore on unsupported platforms.
  }
}

Future<void> _preloadDesktopSystemFonts() async {
  if (kIsWeb) return;
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!isDesktop) return;
  try {
    final sf = SystemFonts();
    // Best-effort: ensure system font families are registered before first frame
    await sf.loadAllFonts();
  } catch (_) {
    // Ignore failures; fallback fonts will still work
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => McpToolService()),
        ChangeNotifierProvider(create: (_) => McpProvider()),
        ChangeNotifierProvider(create: (_) => AssistantProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => QuickPhraseProvider()),
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        ChangeNotifierProvider(
          create: (ctx) => BackupProvider(
            chatService: ctx.read<ChatService>(),
            initialConfig: ctx.read<SettingsProvider>().webDavConfig,
          ),
        ),
        ChangeNotifierProvider(create: (_) => StorageProvider()),
        ChangeNotifierProvider(create: (_) => LogSettingsProvider()),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          // Apply global proxy overrides when settings change
          settings.applyGlobalProxyOverridesIfNeeded();
          // One-time app update check after first build
          if (settings.showAppUpdates && !_didCheckUpdates) {
            _didCheckUpdates = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try { context.read<UpdateProvider>().checkForUpdates(); } catch (e, s) { Logger.w(LogTags.update, 'checkForUpdates failed', e, s); }
            });
          }
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              final isAndroid = Theme.of(context).platform == TargetPlatform.android;
              // Update dynamic color capability for settings UI (avoid notify during build)
              final dynSupported = isAndroid && (lightDynamic != null || darkDynamic != null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  settings.setDynamicColorSupported(dynSupported);
                } catch (e, s) { Logger.w(LogTags.settings, 'setDynamicColorSupported failed', e, s); }
              });

              // Android-only: ensure background execution matches setting and prepare notifications if needed
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  if (Platform.isAndroid) {
                    final mode = settings.androidBackgroundChatMode;
                    if (mode != AndroidBackgroundChatMode.off) {
                      // Enable only if currently disabled to avoid duplicate ROM prompts
                      try {
                        final already = await AndroidBackgroundManager.isEnabled();
                        if (!already) {
                          await AndroidBackgroundManager.ensureInitialized(
                            notificationTitle: context.l10n.androidBackgroundNotificationTitle,
                            notificationText: context.l10n.androidBackgroundNotificationText,
                          );
                          await AndroidBackgroundManager.setEnabled(true);
                        }
                      } catch (e, s) { Logger.w(LogTags.background, 'AndroidBackground init failed', e, s); }
                      if (mode == AndroidBackgroundChatMode.onNotify) {
                        await NotificationService.ensureInitialized();
                        await NotificationService.ensureAndroidNotificationsPermission();
                      }
                    }
                  }
                } catch (e, s) { Logger.w(LogTags.background, 'Android background setup failed', e, s); }
              });

              final useDyn = isAndroid && settings.useDynamicColor;
              final palette = ThemePalettes.byId(settings.themePaletteId);

              final light = buildLightThemeForScheme(
                palette.light,
                dynamicScheme: useDyn ? lightDynamic : null,
                pureBackground: settings.usePureBackground,
              );
              final dark = buildDarkThemeForScheme(
                palette.dark,
                dynamicScheme: useDyn ? darkDynamic : null,
                pureBackground: settings.usePureBackground,
              );
              // Resolve effective app font family (system/Google/local alias)
              String? _effectiveAppFontFamily() {
                final fam = settings.appFontFamily;
                if (fam == null || fam.isEmpty) return null;
                if (settings.appFontIsGoogle) {
                  try {
                    final s = GoogleFonts.getFont(fam);
                    return s.fontFamily ?? fam;
                  } catch (e, s) {
                    Logger.d(LogTags.settings, 'GoogleFonts.getFont failed for $fam, fallback to family name', e, s);
                    return fam;
                  }
                }
                return fam;
              }
              final effectiveAppFont = _effectiveAppFontFamily();

              // Apply user-selected app font to theme text styles and app bar
              ThemeData _applyAppFont(ThemeData base) {
                if (effectiveAppFont == null || effectiveAppFont.isEmpty) return base;
                TextStyle? _f(TextStyle? s) => s?.copyWith(fontFamily: effectiveAppFont);
                TextTheme _apply(TextTheme t) => t.copyWith(
                      displayLarge: _f(t.displayLarge),
                      displayMedium: _f(t.displayMedium),
                      displaySmall: _f(t.displaySmall),
                      headlineLarge: _f(t.headlineLarge),
                      headlineMedium: _f(t.headlineMedium),
                      headlineSmall: _f(t.headlineSmall),
                      titleLarge: _f(t.titleLarge),
                      titleMedium: _f(t.titleMedium),
                      titleSmall: _f(t.titleSmall),
                      bodyLarge: _f(t.bodyLarge),
                      bodyMedium: _f(t.bodyMedium),
                      bodySmall: _f(t.bodySmall),
                      labelLarge: _f(t.labelLarge),
                      labelMedium: _f(t.labelMedium),
                      labelSmall: _f(t.labelSmall),
                    );
                final bar = base.appBarTheme;
                final appBar = bar.copyWith(
                  titleTextStyle: (bar.titleTextStyle ?? const TextStyle()).copyWith(fontFamily: effectiveAppFont),
                  toolbarTextStyle: (bar.toolbarTextStyle ?? const TextStyle()).copyWith(fontFamily: effectiveAppFont),
                );
                // Apply as default family to all text in ThemeData
                return base.copyWith(
                  textTheme: _apply(base.textTheme),
                  primaryTextTheme: _apply(base.primaryTextTheme),
                  appBarTheme: appBar,
                );
              }
              final themedLight = _applyAppFont(light);
              final themedDark = _applyAppFont(dark);

              // builder 闭包
              Widget appBuilder(BuildContext ctx, Widget? child) {
                final bright = Theme.of(ctx).brightness;
                final overlay = bright == Brightness.dark
                    ? const SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarIconBrightness: Brightness.light,
                        statusBarBrightness: Brightness.dark,
                        systemNavigationBarColor: Colors.transparent,
                        systemNavigationBarIconBrightness: Brightness.light,
                        systemNavigationBarDividerColor: Colors.transparent,
                        systemNavigationBarContrastEnforced: false,
                      )
                    : const SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarIconBrightness: Brightness.dark,
                        statusBarBrightness: Brightness.light,
                        systemNavigationBarColor: Colors.transparent,
                        systemNavigationBarIconBrightness: Brightness.dark,
                        systemNavigationBarDividerColor: Colors.transparent,
                        systemNavigationBarContrastEnforced: false,
                      );
                if (!_didEnsureAssistants) {
                  _didEnsureAssistants = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    try { ctx.read<AssistantProvider>().ensureDefaults(ctx); } catch (e, s) { Logger.w(LogTags.assistant, 'ensureDefaults failed', e, s); }
                    try { ctx.read<ChatService>().setDefaultConversationTitle(ctx.l10n.chatServiceDefaultConversationTitle); } catch (e, s) { Logger.w(LogTags.chat, 'setDefaultConversationTitle failed', e, s); }
                    try { ctx.read<UserProvider>().setDefaultNameIfUnset(ctx.l10n.userProviderDefaultUserName); } catch (e, s) { Logger.w(LogTags.user, 'setDefaultNameIfUnset failed', e, s); }
                  });
                }
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlay,
                  child: effectiveAppFont == null
                      ? AppSnackBarOverlay(child: child ?? const SizedBox.shrink())
                      : DefaultTextStyle.merge(
                          style: TextStyle(fontFamily: effectiveAppFont),
                          child: AppSnackBarOverlay(child: child ?? const SizedBox.shrink()),
                        ),
                );
              }

              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'MiniMe-Core',
                locale: settings.appLocaleForMaterialApp,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: themedLight,
                darkTheme: themedDark,
                themeMode: settings.themeMode,
                navigatorObservers: <NavigatorObserver>[routeObserver],
                home: _selectHome(),
                builder: appBuilder,
              );
            },
          );
        },
      ),
    );
  }
}

Widget _selectHome() {
  // Mobile remains the default platform. Desktop is an added platform.
  if (kIsWeb) return const HomePage();
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  return isDesktop ? const DesktopHomePage() : const HomePage();
}
 
// Overrides logic is implemented within SettingsProvider now.
