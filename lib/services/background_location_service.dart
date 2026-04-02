import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await Firebase.initializeApp();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Bus Tracking Active",
      content: "Battery Optimized Mode",
    );
  }

  /// ✅ Permission Check
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return;
  }

  /// ✅ Optimized Location Settings
  const locationSettings = LocationSettings(
    accuracy: LocationAccuracy.low, // 👈 lower heat
    distanceFilter: 40, // 👈 update only after 40m movement
  );

  StreamSubscription<Position>? positionStream;

  DateTime lastUpdateTime = DateTime.now();

  positionStream =
      Geolocator.getPositionStream(locationSettings: locationSettings).listen((
        Position position,
      ) async {
        /// ⏱️ Throttle updates (minimum 8 seconds gap)
        if (DateTime.now().difference(lastUpdateTime).inSeconds < 8) {
          return;
        }

        lastUpdateTime = DateTime.now();

        try {
          await FirebaseFirestore.instance
              .collection("bus_location")
              .doc("bus_1")
              .update({
                "latitude": position.latitude,
                "longitude": position.longitude,
                "updatedAt": FieldValue.serverTimestamp(),
              });
        } catch (e) {
          // silently fail to prevent crash
        }
      });

  /// 🛑 Stop service properly
  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });
}
