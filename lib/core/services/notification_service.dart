import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// 🔔 INITIALIZE NOTIFICATION
  static Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings);

    final androidNotifications = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    /// 🔥 Android 13+ Runtime Permission
    await androidNotifications?.requestNotificationsPermission();

    _initialized = true;
  }

  /// 🔔 SHOW BUS NEAR NOTIFICATION
  static Future<void> showBusNearNotification(String busNo) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'bus_channel',
          'Bus Alerts',
          channelDescription: 'Notification when bus is near',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      1,
      "🚌 Bus $busNo is Near!",
      "Your bus is approaching. Get ready!",
      details,
    );
  }

  /// 🔔 GENERIC NOTIFICATION
  static Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'bus_channel',
          'Bus Alerts',
          channelDescription: 'General bus notifications',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
