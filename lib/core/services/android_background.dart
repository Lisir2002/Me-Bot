import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'logging/logger.dart';
import 'logging/log_tags.dart';

/// Simple manager for enabling/disabling background execution on Android.
/// All calls are no-ops on non-Android platforms.
class AndroidBackgroundManager {
  static bool _initialized = false;

  /// Initialize the plugin once and request needed permissions.
  static Future<bool> ensureInitialized({String? notificationTitle, String? notificationText}) async {
    if (!Platform.isAndroid) return false;
    if (_initialized) return true;
    Logger.i(LogTags.background, 'ensureInitialized: initializing FlutterBackground');
    try {
      final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: notificationTitle ?? 'MiniMe-Core is running',
        notificationText: notificationText ?? 'Keeping chat generation alive in background',
        notificationImportance: AndroidNotificationImportance.normal,
        // Explicitly use app launcher icon from mipmap to avoid resource resolution issues
        notificationIcon: const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      final ok = await FlutterBackground.initialize(androidConfig: androidConfig);
      _initialized = ok;
      Logger.i(LogTags.background, 'ensureInitialized result: $ok');
      return ok;
    } catch (e) {
      Logger.e(LogTags.background, 'ensureInitialized failed: $e');
      return false;
    }
  }

  /// Enable/disable background execution. Requires [ensureInitialized] to have run.
  static Future<void> setEnabled(bool enable) async {
    if (!Platform.isAndroid) return;
    Logger.i(LogTags.background, 'setEnabled: enable=$enable currentlyInit=$_initialized');
    try {
      // Short-circuit if state already matches
      try {
        final current = await FlutterBackground.isBackgroundExecutionEnabled;
        if (current == enable) {
          Logger.d(LogTags.background, 'setEnabled: already in state enable=$enable, skip');
          return;
        }
      } catch (_) {}

      if (enable) {
        if (!_initialized) {
          // Initialize only when enabling, since this may trigger permission dialogs
          await ensureInitialized();
        }
        await FlutterBackground.enableBackgroundExecution();
        Logger.i(LogTags.background, 'background execution enabled');
      } else {
        // Try to disable without forcing initialization to avoid permission prompts
        try {
          await FlutterBackground.disableBackgroundExecution();
          Logger.i(LogTags.background, 'background execution disabled');
        } catch (e) {
          Logger.w(LogTags.background, 'disableBackgroundExecution failed: $e');
        }
      }
    } catch (e) {
      Logger.e(LogTags.background, 'setEnabled failed: $e');
    }
  }

  /// Convenience to query whether background execution is currently enabled.
  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return FlutterBackground.isBackgroundExecutionEnabled;
    } catch (_) {
      return false;
    }
  }
}
