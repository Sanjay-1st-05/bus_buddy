import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/notification_service.dart';

class StudentTrackPage extends StatefulWidget {
  final String busId;

  const StudentTrackPage({super.key, required this.busId});

  @override
  State<StudentTrackPage> createState() => _StudentTrackPageState();
}

class _StudentTrackPageState extends State<StudentTrackPage> {
  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot>? _locationSub;

  LatLng _busPosition = const LatLng(11.0168, 76.9558);
  LatLng? _studentPosition;
  Marker? _busMarker;

  Set<Polyline> _polylines = {};

  double? _distanceKm;
  int? _etaMinutes;

  bool _nearNotified = false;
  bool _arrivedNotified = false;

  // 🔥 ROUTE START & END (CHANGE THESE)
  final LatLng _startPoint = const LatLng(11.0200, 76.9500);
  final LatLng _endPoint = const LatLng(11.0400, 76.9800);

  @override
  void initState() {
    super.initState();
    _getStudentLocation();
    _createPolyline();
    _listenBusLocation();
  }

  // 🔹 Get student location once
  Future<void> _getStudentLocation() async {
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );

    setState(() {
      _studentPosition = LatLng(pos.latitude, pos.longitude);
    });
  }

  // 🔥 Create route polyline
  void _createPolyline() {
    Polyline route = Polyline(
      polylineId: const PolylineId("route"),
      color: Colors.indigo,
      width: 5,
      points: [_startPoint, _endPoint],
    );

    setState(() {
      _polylines.add(route);
    });
  }

  // 🔥 Smooth marker animation
  void _animateMarker(LatLng newPosition) {
    LatLng oldPosition = _busPosition;

    const int steps = 20;
    double latStep = (newPosition.latitude - oldPosition.latitude) / steps;
    double lngStep = (newPosition.longitude - oldPosition.longitude) / steps;

    for (int i = 1; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        LatLng intermediate = LatLng(
          oldPosition.latitude + (latStep * i),
          oldPosition.longitude + (lngStep * i),
        );

        setState(() {
          _busPosition = intermediate;
          _busMarker = Marker(
            markerId: MarkerId(widget.busId),
            position: intermediate,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          );
        });
      });
    }
  }

  // 🔥 Distance formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6371;
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  void _calculateETA(LatLng busPos) {
    if (_studentPosition == null) return;

    double distance = _calculateDistance(
      _studentPosition!.latitude,
      _studentPosition!.longitude,
      busPos.latitude,
      busPos.longitude,
    );

    int minutes = ((distance / 35) * 60).round();

    if (distance <= 1 && !_nearNotified) {
      NotificationService.showNotification("Bus Near", "Bus arriving soon 🚍");
      _nearNotified = true;
    }

    if (distance <= 0.1 && !_arrivedNotified) {
      NotificationService.showNotification(
        "Bus Arrived",
        "Bus reached your location 🎉",
      );
      _arrivedNotified = true;
    }

    setState(() {
      _distanceKm = distance;
      _etaMinutes = minutes;
    });
  }

  void _listenBusLocation() {
    _locationSub = FirebaseFirestore.instance
        .collection("bus_location")
        .doc(widget.busId)
        .snapshots()
        .listen((doc) {
          if (!doc.exists) return;

          final data = doc.data() as Map<String, dynamic>;

          final double lat = (data["latitude"] ?? 0).toDouble();
          final double lng = (data["longitude"] ?? 0).toDouble();

          final newPosition = LatLng(lat, lng);

          _animateMarker(newPosition);
          _calculateETA(newPosition);

          _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
        });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Tracking ${widget.busId}")),
      body: Column(
        children: [
          if (_distanceKm != null && _etaMinutes != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.indigo.shade50,
              child: Column(
                children: [
                  Text(
                    "Distance: ${_distanceKm!.toStringAsFixed(2)} km",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "ETA: $_etaMinutes minutes",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _busPosition,
                zoom: 15,
              ),
              markers: _busMarker != null ? {_busMarker!} : {},
              polylines: _polylines,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
          ),
        ],
      ),
    );
  }
}
