import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

/// Must be a top-level function (Firebase requirement) — handles messages
/// that arrive while the app is fully backgrounded/terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: FCM already shows a system-tray notification for background/
  // terminated messages using the payload's "notification" block. This
  // handler only needs to exist for FCM to deliver silently-tagged data.
}

/// Wires up Firebase Cloud Messaging: requests permission, registers this
/// device's token with the backend, and shows a local notification for
/// messages that arrive while the app is in the foreground (FCM does not
/// auto-display those).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'default_channel',
    'General Notifications',
    description: 'App announcements and reminders',
    importance: Importance.high,
  );

  /// Call once, after Firebase.initializeApp() has succeeded and the user
  /// is authenticated (registering a token needs a logged-in user).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen(_registerToken);

      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    } catch (e) {
      developer.log('Push notification init failed: $e',
          name: 'PushNotificationService');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await ApiService().registerFcmToken(token);
    } catch (e) {
      developer.log('Failed to register FCM token: $e',
          name: 'PushNotificationService');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

/// Initializes Firebase itself. Safe to call even before a Firebase project
/// has been set up — returns false instead of throwing, so the rest of the
/// app (including the update-nudge feature) keeps working regardless.
Future<bool> initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    return true;
  } catch (e) {
    developer.log('Firebase not configured yet: $e',
        name: 'PushNotificationService');
    return false;
  }
}
