import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'logging/logger.dart';
import 'logging/log_tags.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'minime-core_bg_chat_v2',
    'Chat Background',
    description: 'Notifications for chat generation status',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid) return;
    if (_inited) return;
    Logger.i(LogTags.notification, 'ensureInitialized: initializing FlutterLocalNotifications');

    // Android initialization
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings init = InitializationSettings(android: androidInit);
    await _plugin.initialize(init);

    // Create channel
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_channel);
      Logger.i(LogTags.notification, 'Notification channel created: ${_channel.id}');
      // Runtime notification permission (Android 13+) should be requested by app UI if needed
    }
    _inited = true;
  }

  /// Ensure Android 13+ notifications permission is granted (no-op on lower versions/other platforms).
  static Future<bool> ensureAndroidNotificationsPermission() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      final enabled = await android.areNotificationsEnabled();
      if (enabled == true) return true;
    } catch (e) {
      Logger.w(LogTags.notification, 'areNotificationsEnabled check failed: $e');
    }
    try {
      final ok = await android.requestNotificationsPermission();
      Logger.i(LogTags.notification, 'requestNotificationsPermission result: $ok');
      return ok ?? false;
    } catch (e) {
      Logger.e(LogTags.notification, 'requestNotificationsPermission failed: $e');
      return false;
    }
  }

  static Future<void> showChatCompleted({String? title, String? body}) async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    Logger.i(LogTags.notification, 'showChatCompleted: title=${title ?? 'default'}');
    await _plugin.show(
      2001, // id
      title ?? 'Generation complete',
      body ?? 'Assistant reply has been generated',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ticker: 'MiniMe-Core',
          styleInformation: const DefaultStyleInformation(true, true),
        ),
      ),
    );
  }
}
