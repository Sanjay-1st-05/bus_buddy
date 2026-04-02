import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'firebase_options.dart';
import 'theme.dart';

import 'ui/splash/splash.dart';
import 'services/background_location_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Firebase initialize
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔥 Local Notification initialize
  await NotificationService.initialize();

  // 🔥 Background service initialize
  await initializeService();

  runApp(const BusBuddyApp());
}

class BusBuddyApp extends StatelessWidget {
  const BusBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESEC BUS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

/// ===============================
/// BACKGROUND SERVICE INITIALIZER
/// ===============================
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'bus_tracking',
      initialNotificationTitle: 'Bus Tracking Active',
      initialNotificationContent: 'Waiting for trip start...',
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
}
