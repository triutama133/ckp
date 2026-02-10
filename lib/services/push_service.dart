import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _local.initialize(settings);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ?? 'Notifikasi';
      final body = message.notification?.body ?? '';
      await _showLocal(title, body);
    });
  }

  Future<void> _registerToken(String token) async {
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'id': '${AuthService.instance.userId}_${token.substring(0, 8)}',
        'user_id': AuthService.instance.userId,
        'token': token,
        'platform': 'mobile',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _showLocal(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'push_notifications',
      'Push Notifications',
      channelDescription: 'Notifikasi push',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _local.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }
}
