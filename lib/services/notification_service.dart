import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for incoming Blousab messages.
/// Notifications require the app process and its Bluetooth/LAN listener to remain alive.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static String? activeConversationId;
  static bool appInForeground = true;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _shownIds = <String>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@android:drawable/sym_def_app_icon');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  Future<void> requestPermission() async {
    if (!_initialized) await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> handleIncomingPayload(String raw, {required String currentUserId}) async {
    try {
      final dynamic value = jsonDecode(raw);
      if (value is! Map) return;
      final type = value['type']?.toString() ?? '';
      if (type == 'profile_card' || type == 'profile_update' || type == 'hello' || type == 'hello_ack') return;
      if (type != 'chat' && type != 'file' && type != 'text') return;
      final senderId = value['senderId']?.toString() ?? '';
      if (senderId.isEmpty || senderId == currentUserId) return;
      final conversationId = value['conversationId']?.toString() ?? '';
      if (appInForeground && activeConversationId != null && activeConversationId == conversationId) return;
      final id = value['id']?.toString() ?? '${senderId}_${value['sentAt']}_${value['text']}';
      if (!_shownIds.add(id)) return;
      if (_shownIds.length > 500) _shownIds.remove(_shownIds.first);
      bool notificationsEnabled = true;
      try {
        final enabledPrefs = await SharedPreferences.getInstance();
        notificationsEnabled = enabledPrefs.getBool('blousab_notifications_enabled') ?? true;
      } catch (_) {}
      // Store metadata only, not message text or attachments, for the in-app inbox.
      try {
        final prefs = await SharedPreferences.getInstance();
        final items = prefs.getStringList('blousab_notifications_v1') ?? <String>[];
        items.insert(0, jsonEncode({
          'id': id, 'sender': value['senderName']?.toString() ?? 'مستخدم بلوساب',
          'type': type, 'conversationId': conversationId,
          'at': DateTime.now().toIso8601String(),
        }));
        if (items.length > 100) items.removeRange(100, items.length);
        await prefs.setStringList('blousab_notifications_v1', items);
      } catch (_) {}
      final senderName = value['senderName']?.toString().trim();
      final title = (senderName == null || senderName.isEmpty) ? 'رسالة جديدة' : senderName;
      final body = type == 'file' ? '📎 أرسل ملفًا' : (value['text']?.toString() ?? 'رسالة جديدة');
      final notificationId = id.hashCode & 0x7fffffff;
      if (!notificationsEnabled) return;
      await _plugin.show(
        notificationId,
        title,
        body.isEmpty ? 'رسالة جديدة' : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'blousab_messages',
            'رسائل بلوساب',
            channelDescription: 'إشعارات الرسائل الجديدة في بلوساب',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            icon: '@android:drawable/sym_def_app_icon',
          ),
        ),
        payload: conversationId,
      );
    } catch (_) {
      // A malformed packet should never interrupt message reception.
    }
  }
}
