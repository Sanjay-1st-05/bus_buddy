import 'dart:async';
import 'dart:convert';
import 'package:esec_bus/ui/auth/login.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool isTripStarted = false;
  Timer? _gpsTimer;

  final String backendUrl =
      "http://10.18.159.88:5000/api/location/update"; // 🔥 change if needed

  /// 🔥 START REAL GPS TRACKING
  Future<void> _startGpsTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied")),
      );
      return;
    }

    // 🔥 Prevent multiple timers
    _gpsTimer?.cancel();

    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        await http.post(
          Uri.parse(backendUrl),
          headers: {"Content-Type": "application/json", "role": "driver"},
          body: jsonEncode({
            "busId": "BUS_01",
            "latitude": position.latitude,
            "longitude": position.longitude,
          }),
        );

        print("GPS Updated: ${position.latitude}, ${position.longitude}");
      } catch (e) {
        print("GPS Error: $e");
      }
    });
  }

  void _startTrip() {
    setState(() {
      isTripStarted = true;
    });

    _startGpsTracking();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Trip Started - Live GPS Enabled")),
    );
  }

  void _stopTrip() {
    _gpsTimer?.cancel();
    _gpsTimer = null;

    setState(() {
      isTripStarted = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Trip Stopped")));
  }

  void _logout() {
    _gpsTimer?.cancel();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Driver Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// BUS CARD
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.directions_bus, size: 40),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Bus 01",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text("Town → College"),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            /// STATUS
            Text("Trip Status", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            Row(
              children: [
                Icon(
                  isTripStarted ? Icons.play_circle : Icons.stop_circle,
                  color: isTripStarted ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  isTripStarted ? "Running" : "Not Started",
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),

            const SizedBox(height: 40),

            /// START / STOP BUTTON
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: isTripStarted ? _stopTrip : _startTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTripStarted ? Colors.red : Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isTripStarted ? "Stop Trip" : "Start Trip",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 30),

            const Text("Note:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "When trip is started, real GPS location is sent to students who can track live movement.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
