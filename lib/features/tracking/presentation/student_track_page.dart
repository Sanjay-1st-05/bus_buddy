import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/core/services/notification_service.dart';
import 'package:esec_bus/features/tracking/services/live_tracking_metrics.dart';
import 'package:esec_bus/features/tracking/services/tracking_presence.dart';
import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';

class StudentTrackPage extends StatefulWidget {
  final String busId;

  const StudentTrackPage({super.key, required this.busId});

  @override
  State<StudentTrackPage> createState() => _StudentTrackPageState();
}

class _StudentTrackPageState extends State<StudentTrackPage>
    with SingleTickerProviderStateMixin {
  static const LatLng _defaultMapCenter = LatLng(11.0168, 76.9558);
  static const Duration _minimumMarkerAnimation = Duration(milliseconds: 800);
  static const Duration _maximumMarkerAnimation = Duration(milliseconds: 2400);
  static const Duration _autoFollowPause = Duration(seconds: 15);

  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _locationSub;
  StreamSubscription<Position>? _studentLocationSub;
  Timer? _predictionTimer;
  Timer? _freshnessTimer;
  Timer? _autoFollowResumeTimer;
  late final AnimationController _markerAnimationController;
  final PredictiveTrackingModule _predictionModule =
      PredictiveTrackingModule.fromConfig(SmartSyncConfig.defaults());
  final List<LocationSample> _locationHistory = [];
  LocationSample? _lastLiveSample;
  bool _isPredictedPosition = false;

  LatLng? _busPosition;
  LatLng? _animationStartPosition;
  LatLng? _animationTargetPosition;
  LatLng? _studentPosition;
  DateTime? _lastUpdatedAt;
  DateTime? _serviceHeartbeatAt;
  double? _busSpeedMetersPerSecond;
  double? _busAccuracyMeters;
  double _displayedHeading = 0;
  double _animationStartHeading = 0;
  double _animationTargetHeading = 0;
  BitmapDescriptor? _busMarkerIcon;

  String _tripStatus = "waiting";
  String _locationMessage = "Waiting for live bus location";

  LiveTrackingMetrics? _metrics;

  bool _nearNotified = false;
  bool _arrivedNotified = false;
  bool _isLoadingStudentLocation = true;
  bool _autoFollowEnabled = true;
  bool _programmaticCameraMove = false;

  bool get _hasLiveBusLocation => _busPosition != null;
  bool get _isBusRunning => _tripStatus == "running";
  TrackingPresence get _trackingPresence => TrackingPresence.evaluate(
    isActive: _isBusRunning,
    hasValidLocation: _hasLiveBusLocation,
    coordinateCapturedAt: _lastUpdatedAt,
    serviceHeartbeatAt: _serviceHeartbeatAt,
    speedMetersPerSecond: _busSpeedMetersPerSecond,
  );

  @override
  void initState() {
    super.initState();
    _markerAnimationController =
        AnimationController(vsync: this, duration: _minimumMarkerAnimation)
          ..addListener(_handleMarkerAnimationTick)
          ..addStatusListener(_handleMarkerAnimationStatus);
    unawaited(_loadBusMarkerIcon());
    _getStudentLocation();
    _listenBusLocation();
    _predictionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updatePrediction(),
    );
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _getStudentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final shouldOpenSettings = mounted
            ? await _showGpsRequiredDialog()
            : false;
        if (shouldOpenSettings == true) {
          await Geolocator.openLocationSettings();
        }
        if (!mounted) return;
        setState(() {
          _isLoadingStudentLocation = false;
          _locationMessage = "Turn on location to calculate ETA";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isLoadingStudentLocation = false;
          _locationMessage = "Location permission needed for ETA";
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!mounted) return;

      _updateStudentPosition(position);
      await _studentLocationSub?.cancel();
      _studentLocationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_updateStudentPosition, onError: _handleStudentLocationError);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingStudentLocation = false;
        _locationMessage = "Unable to get your location for ETA";
      });
    }
  }

  void _updateStudentPosition(Position position) {
    if (!mounted) return;
    final newStudentPosition = LatLng(position.latitude, position.longitude);
    setState(() {
      _studentPosition = newStudentPosition;
      _isLoadingStudentLocation = false;
    });

    final busPosition = _busPosition;
    if (busPosition != null) _updateMetrics(busPosition);
    unawaited(_fitTrackingBounds());
  }

  void _handleStudentLocationError(Object _) {
    if (!mounted || _studentPosition != null) return;
    setState(() {
      _isLoadingStudentLocation = false;
      _locationMessage = "Unable to update your location for ETA";
    });
  }

  void _listenBusLocation() {
    _locationSub = FirebaseFirestore.instance
        .collection(FirestoreCollections.buses)
        .doc(widget.busId)
        .snapshots()
        .listen(
          _handleLocationSnapshot,
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _tripStatus = "error";
              _locationMessage = "Unable to load live bus status";
            });
          },
        );
  }

  Future<bool?> _showGpsRequiredDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Turn on GPS"),
          content: const Text(
            "Bus tracking can show your ETA only when your phone GPS is turned on.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Later"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Turn On GPS"),
            ),
          ],
        );
      },
    );
  }

  void _handleLocationSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!mounted) return;

    if (!doc.exists) {
      setState(() {
        _tripStatus = "not_configured";
        _locationMessage = "Live tracking is not configured for this bus";
        _lastUpdatedAt = null;
        _serviceHeartbeatAt = null;
      });
      return;
    }

    final busData = doc.data() ?? {};
    final data = firestoreMap(busData["tracking"]);
    final currentPoint = firestoreMap(data["currentPoint"]);
    final status = _readStatus(data);
    final serviceHeartbeatAt = _readTimestamp(data["serviceHeartbeatAt"]);
    final lastUpdatedAt =
        _readTimestamp(data["lastUpdatedAt"]) ??
        _readTimestamp(busData["updatedAt"]);
    final latitude = _readDouble(currentPoint["latitude"]);
    final longitude = _readDouble(currentPoint["longitude"]);
    final hasValidPosition = _isValidCoordinate(latitude, longitude);

    if (!hasValidPosition) {
      setState(() {
        _tripStatus = status;
        _lastUpdatedAt = lastUpdatedAt;
        _serviceHeartbeatAt = serviceHeartbeatAt;
        _locationMessage = _buildLocationMessage(status, false);
        _metrics = null;
      });
      return;
    }

    final newPosition = LatLng(latitude!, longitude!);
    final capturedAt =
        _readTimestamp(currentPoint["capturedAt"]) ??
        lastUpdatedAt ??
        DateTime.now();
    final sample = LocationSample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: _readDouble(currentPoint["speed"]),
      headingDegrees: _readDouble(currentPoint["heading"]),
      accuracyMeters: _readDouble(currentPoint["accuracy"]),
      capturedAt: capturedAt,
    );
    final previousSample = _lastLiveSample;
    final transitionDuration = _transitionDuration(
      previousSample?.capturedAt,
      capturedAt,
    );
    final isNewSample =
        previousSample == null ||
        previousSample.capturedAt != sample.capturedAt ||
        previousSample.latitude != sample.latitude ||
        previousSample.longitude != sample.longitude;
    _lastLiveSample = sample;
    if (isNewSample) {
      _locationHistory.add(sample);
      if (_locationHistory.length > 30) _locationHistory.removeAt(0);
    }
    _isPredictedPosition = false;
    final targetHeading = _resolveHeading(
      from: _busPosition,
      to: newPosition,
      reportedHeading: sample.headingDegrees,
    );
    final isFirstPosition = _busPosition == null;

    setState(() {
      _tripStatus = status;
      _lastUpdatedAt = capturedAt;
      _serviceHeartbeatAt = serviceHeartbeatAt;
      _locationMessage = _buildLocationMessage(status, true);
      _busSpeedMetersPerSecond = sample.speedMetersPerSecond;
      _busAccuracyMeters = sample.accuracyMeters;
      if (isFirstPosition) {
        _busPosition = newPosition;
        _displayedHeading = targetHeading;
      }
    });

    if (isFirstPosition) {
      _updateMetrics(newPosition);
    } else if (_busPosition != newPosition) {
      _animateMarker(
        newPosition,
        targetHeading: targetHeading,
        duration: transitionDuration,
      );
    } else {
      _updateMetrics(newPosition);
    }

    unawaited(_fitTrackingBounds(busOverride: newPosition));
  }

  void _updatePrediction() {
    final sample = _lastLiveSample;
    if (!mounted || !_isBusRunning || sample == null) return;
    if (_trackingPresence.status == TrackingPresenceStatus.stationary) return;
    if (DateTime.now().difference(sample.capturedAt) <
        const Duration(seconds: 10)) {
      return;
    }

    final result = _predictionModule.predict(
      PredictionInput(
        previousGps: sample,
        predictionTime: DateTime.now(),
        hasLiveGps: false,
        historicalMovement: List.unmodifiable(_locationHistory),
      ),
    );
    final predicted = result.predictedPosition;
    if (!result.isActive || predicted == null) return;

    final position = LatLng(predicted.latitude, predicted.longitude);
    setState(() {
      _isPredictedPosition = true;
      _locationMessage =
          "Predicted location (${(result.confidenceScore * 100).round()}% confidence)";
    });
    _animateMarker(
      position,
      targetHeading: _resolveHeading(
        from: _busPosition,
        to: position,
        reportedHeading: sample.headingDegrees,
      ),
      duration: const Duration(milliseconds: 1200),
    );
    unawaited(_fitTrackingBounds(busOverride: position));
  }

  String _readStatus(Map<String, dynamic> data) {
    final statusValue = data["status"];
    if (statusValue is String && statusValue.trim().isNotEmpty) {
      return statusValue.trim().toLowerCase();
    }

    return data["isActive"] == true ? "running" : "stopped";
  }

  String _buildLocationMessage(String status, bool hasValidPosition) {
    if (!hasValidPosition) {
      return status == "running"
          ? "Trip is running, waiting for first GPS update"
          : "Bus location is not available yet";
    }

    if (status == "running") {
      return "Live location active";
    }

    if (status == "stopped") {
      return "Trip is stopped";
    }

    return "Latest bus location";
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  bool _isValidCoordinate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  Future<void> _loadBusMarkerIcon() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(size / 2, size / 2 + 3),
      39,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      39,
      Paint()..color = const Color(0xFF1565C0),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      35,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final bodyPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(31, 20, 34, 56),
        const Radius.circular(8),
      ),
      bodyPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(36, 27, 24, 17),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF90CAF9),
    );
    canvas.drawRect(
      const Rect.fromLTWH(36, 49, 24, 12),
      Paint()..color = const Color(0xFFE3F2FD),
    );
    canvas.drawCircle(
      const Offset(38, 68),
      4,
      Paint()..color = const Color(0xFF263238),
    );
    canvas.drawCircle(
      const Offset(58, 68),
      4,
      Paint()..color = const Color(0xFF263238),
    );
    canvas.drawCircle(
      const Offset(38, 24),
      2.4,
      Paint()..color = const Color(0xFFFFD54F),
    );
    canvas.drawCircle(
      const Offset(58, 24),
      2.4,
      Paint()..color = const Color(0xFFFFD54F),
    );

    final image = await recorder.endRecording().toImage(
      size.round(),
      size.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted || data == null) return;

    setState(() {
      _busMarkerIcon = BitmapDescriptor.bytes(
        data.buffer.asUint8List(),
        width: 48,
        height: 48,
      );
    });
  }

  Duration _transitionDuration(DateTime? previous, DateTime current) {
    if (previous == null) return _minimumMarkerAnimation;
    final elapsed = current.difference(previous);
    if (elapsed <= Duration.zero) return _minimumMarkerAnimation;

    return Duration(
      milliseconds: elapsed.inMilliseconds.clamp(
        _minimumMarkerAnimation.inMilliseconds,
        _maximumMarkerAnimation.inMilliseconds,
      ),
    );
  }

  double _resolveHeading({
    required LatLng? from,
    required LatLng to,
    double? reportedHeading,
  }) {
    if (reportedHeading != null &&
        reportedHeading.isFinite &&
        reportedHeading >= 0 &&
        reportedHeading < 360) {
      return reportedHeading;
    }
    if (from == null) return _displayedHeading;

    final movementDistance = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (movementDistance < 1) return _displayedHeading;

    return Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  void _animateMarker(
    LatLng newPosition, {
    required double targetHeading,
    required Duration duration,
  }) {
    final oldPosition = _busPosition;
    if (oldPosition == null) {
      setState(() {
        _busPosition = newPosition;
        _displayedHeading = targetHeading;
      });
      _updateMetrics(newPosition);
      return;
    }

    _markerAnimationController.stop();
    _animationStartPosition = oldPosition;
    _animationTargetPosition = newPosition;
    _animationStartHeading = _displayedHeading;
    _animationTargetHeading = targetHeading;
    _markerAnimationController.duration = duration;
    _markerAnimationController.forward(from: 0);
  }

  void _handleMarkerAnimationTick() {
    final start = _animationStartPosition;
    final target = _animationTargetPosition;
    if (!mounted || start == null || target == null) return;

    final progress = Curves.easeInOutCubic.transform(
      _markerAnimationController.value,
    );
    final position = LatLng(
      ui.lerpDouble(start.latitude, target.latitude, progress)!,
      ui.lerpDouble(start.longitude, target.longitude, progress)!,
    );
    final heading = _interpolateHeading(
      _animationStartHeading,
      _animationTargetHeading,
      progress,
    );
    final metrics = _calculateMetrics(position);

    setState(() {
      _busPosition = position;
      _displayedHeading = heading;
      if (metrics != null) _metrics = metrics;
    });
    if (metrics != null) _handleProximityNotifications(metrics);
  }

  void _handleMarkerAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final target = _animationTargetPosition;
    if (target == null) return;

    final metrics = _calculateMetrics(target);
    setState(() {
      _busPosition = target;
      _displayedHeading = _animationTargetHeading;
      if (metrics != null) _metrics = metrics;
    });
    if (metrics != null) _handleProximityNotifications(metrics);
  }

  double _interpolateHeading(double start, double target, double progress) {
    final delta = ((target - start + 540) % 360) - 180;
    return (start + (delta * progress) + 360) % 360;
  }

  LiveTrackingMetrics? _calculateMetrics(LatLng busPosition) {
    final studentPosition = _studentPosition;
    if (studentPosition == null) return null;

    final now = DateTime.now();
    return LiveTrackingMetrics.calculate(
      busLocation: LocationSample(
        latitude: busPosition.latitude,
        longitude: busPosition.longitude,
        speedMetersPerSecond: _busSpeedMetersPerSecond,
        capturedAt: _lastUpdatedAt ?? now,
      ),
      studentLocation: LocationSample(
        latitude: studentPosition.latitude,
        longitude: studentPosition.longitude,
        capturedAt: now,
      ),
      isTripRunning: _isBusRunning,
    );
  }

  void _handleProximityNotifications(LiveTrackingMetrics metrics) {
    if (_isBusRunning && metrics.distanceMeters <= 1000 && !_nearNotified) {
      NotificationService.showNotification("Bus Near", "Bus arriving soon");
      _nearNotified = true;
    }

    if (_isBusRunning && metrics.distanceMeters <= 100 && !_arrivedNotified) {
      NotificationService.showNotification(
        "Bus Arrived",
        "Bus reached your location",
      );
      _arrivedNotified = true;
    }
  }

  void _updateMetrics(LatLng busPosition) {
    final metrics = _calculateMetrics(busPosition);
    if (!mounted || metrics == null) return;
    _handleProximityNotifications(metrics);

    setState(() {
      _metrics = metrics;
    });
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    if (_busPosition != null) {
      markers.add(
        Marker(
          markerId: MarkerId(widget.busId),
          position: _busPosition!,
          rotation: _displayedHeading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: "Bus ${widget.busId}",
            snippet: _isPredictedPosition
                ? "Predicted position"
                : "Live position",
          ),
          icon:
              _busMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    if (_studentPosition case final studentPosition?) {
      markers.add(
        Marker(
          markerId: const MarkerId('student_location'),
          position: studentPosition,
          infoWindow: const InfoWindow(title: "Your location"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};
    if (_locationHistory.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('live_bus_trail'),
          points: _locationHistory
              .map((sample) => LatLng(sample.latitude, sample.longitude))
              .toList(growable: false),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
          width: 4,
          geodesic: true,
        ),
      );
    }

    final busPosition = _busPosition;
    final studentPosition = _studentPosition;
    if (busPosition != null && studentPosition != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('bus_to_student'),
          points: [busPosition, studentPosition],
          color: Theme.of(context).colorScheme.primary,
          width: 5,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          patterns: [PatternItem.dash(22), PatternItem.gap(12)],
        ),
      );
    }

    return polylines;
  }

  Color _statusColor() {
    if (_metrics?.etaState == LiveEtaState.arrived) return Colors.green;
    if ((_metrics?.distanceMeters ?? double.infinity) <= 500 && _isBusRunning) {
      return Colors.deepOrange;
    }
    switch (_trackingPresence.status) {
      case TrackingPresenceStatus.delayed:
        return Colors.orange;
      case TrackingPresenceStatus.stationary:
        return Colors.teal;
      case TrackingPresenceStatus.startingGps:
        return Colors.blueGrey;
      case TrackingPresenceStatus.live:
      case TrackingPresenceStatus.stopped:
        break;
    }
    switch (_tripStatus) {
      case "running":
        return Colors.green;
      case "stopped":
        return Colors.red;
      case "error":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _statusText() {
    return _liveStatusText();
  }

  String _liveStatusText() {
    if (_metrics?.etaState == LiveEtaState.arrived) return "Arrived";

    switch (_trackingPresence.status) {
      case TrackingPresenceStatus.delayed:
        return _lastUpdatedAt == null ? "No Live Signal" : "GPS Lost";
      case TrackingPresenceStatus.stationary:
        return "Bus stopped";
      case TrackingPresenceStatus.startingGps:
        return "No Live Signal";
      case TrackingPresenceStatus.live:
      case TrackingPresenceStatus.stopped:
        break;
    }

    if (!_isBusRunning) return "Bus stopped";
    final distance = _metrics?.distanceMeters;
    if (distance != null && distance <= 500) return "Arriving soon";
    final speed = _busSpeedMetersPerSecond ?? 0;
    if (speed >= LiveTrackingMetrics.minimumMovingSpeedMetersPerSecond) {
      if (distance != null && distance <= 2000) return "Bus is approaching";
      return "Bus moving";
    }

    switch (_tripStatus) {
      case "running":
        return "Bus stopped";
      case "stopped":
        return "Bus stopped";
      case "not_configured":
        return "No Live Signal";
      case "error":
        return "GPS Lost";
      default:
        return "No Live Signal";
    }
  }

  String _freshnessText() {
    final lastUpdatedAt = _lastUpdatedAt;
    if (lastUpdatedAt == null) return "Not available";

    final difference = DateTime.now().difference(lastUpdatedAt);
    if (difference.isNegative || difference.inSeconds < 5) return "Just now";
    if (difference.inMinutes < 1) {
      return "${difference.inSeconds} sec ago";
    }
    if (difference.inMinutes < 60) {
      final unit = difference.inMinutes == 1 ? "min" : "mins";
      return "${difference.inMinutes} $unit ago";
    }

    final unit = difference.inHours == 1 ? "hr" : "hrs";
    return "${difference.inHours} $unit ago";
  }

  String _displayLocationMessage() {
    if (_isPredictedPosition) {
      return "Estimated position during a brief GPS gap";
    }
    if (!_isPredictedPosition) {
      switch (_trackingPresence.status) {
        case TrackingPresenceStatus.stationary:
          return "Live connection active";
        case TrackingPresenceStatus.startingGps:
          return "Acquiring the first bus position";
        case TrackingPresenceStatus.delayed:
          return _lastUpdatedAt == null
              ? "No live bus position has been received"
              : "The latest bus position is no longer fresh";
        case TrackingPresenceStatus.live:
        case TrackingPresenceStatus.stopped:
          break;
      }
    }
    return _liveStatusText();
  }

  String? _driverGpsDetails() {
    if (_busPosition == null) return null;
    final speedKmh = (_busSpeedMetersPerSecond ?? 0) * 3.6;
    final accuracy = _busAccuracyMeters;
    final accuracyText = accuracy == null ? "" : " • ±${accuracy.round()} m";
    return "Driver phone GPS • ${speedKmh.toStringAsFixed(0)} km/h$accuracyText";
  }

  Widget _buildStatusPanel() {
    final metrics = _metrics;
    final distanceValue =
        metrics?.distanceLabel ??
        (_hasLiveBusLocation ? "Location needed" : "No signal");
    final etaValue =
        metrics?.etaLabel ??
        (_hasLiveBusLocation ? "Location needed" : "No signal");

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Bus ${widget.busId}",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _displayLocationMessage(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusBadge(text: _statusText(), color: _statusColor()),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.update_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    "Updated",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _freshnessText(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (_driverGpsDetails() case final details?) ...[
              const SizedBox(height: 7),
              Text(
                details,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_studentPosition == null && !_isLoadingStudentLocation) ...[
              const SizedBox(height: 7),
              Text(
                _locationMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _LiveMetricCard(
                    label: "Distance",
                    value: distanceValue,
                    icon: Icons.near_me_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LiveMetricCard(
                    label: "ETA",
                    value: etaValue,
                    icon: Icons.schedule_rounded,
                    color: metrics?.etaState == LiveEtaState.arrived
                        ? Colors.green
                        : Colors.deepOrange,
                  ),
                ),
              ],
            ),
            if (metrics?.usesEstimatedSpeed == true) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      "ETA estimated using average moving speed",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (_isLoadingStudentLocation) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    if (_hasLiveBusLocation) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.gps_not_fixed_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                "Map follows the bus after the first valid GPS update.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fitTrackingBounds({
    LatLng? busOverride,
    bool force = false,
  }) async {
    final controller = _mapController;
    final busPosition = busOverride ?? _animationTargetPosition ?? _busPosition;
    if (controller == null ||
        busPosition == null ||
        (!_autoFollowEnabled && !force)) {
      return;
    }

    final studentPosition = _studentPosition;
    CameraUpdate update;
    if (studentPosition == null) {
      update = CameraUpdate.newCameraPosition(
        CameraPosition(target: busPosition, zoom: 16),
      );
    } else {
      final separation = Geolocator.distanceBetween(
        busPosition.latitude,
        busPosition.longitude,
        studentPosition.latitude,
        studentPosition.longitude,
      );
      if (separation < 40) {
        update = CameraUpdate.newCameraPosition(
          CameraPosition(target: busPosition, zoom: 17),
        );
      } else {
        update = CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              math.min(busPosition.latitude, studentPosition.latitude),
              math.min(busPosition.longitude, studentPosition.longitude),
            ),
            northeast: LatLng(
              math.max(busPosition.latitude, studentPosition.latitude),
              math.max(busPosition.longitude, studentPosition.longitude),
            ),
          ),
          86,
        );
      }
    }

    _programmaticCameraMove = true;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      // The platform map may still be laying out immediately after creation.
    } finally {
      if (mounted) _programmaticCameraMove = false;
    }
  }

  void _handleCameraMoveStarted() {
    if (_programmaticCameraMove) return;
    _autoFollowResumeTimer?.cancel();
    if (_autoFollowEnabled && mounted) {
      setState(() {
        _autoFollowEnabled = false;
      });
    }
    _autoFollowResumeTimer = Timer(_autoFollowPause, _resumeAutoFollow);
  }

  void _resumeAutoFollow() {
    _autoFollowResumeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _autoFollowEnabled = true;
    });
    unawaited(_fitTrackingBounds(force: true));
  }

  Widget _buildAutoFollowControl() {
    if (_autoFollowEnabled || !_hasLiveBusLocation) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 16,
      bottom: 22,
      child: FilledButton.icon(
        onPressed: _resumeAutoFollow,
        icon: const Icon(Icons.gps_fixed_rounded, size: 18),
        label: const Text("Resume live"),
        style: FilledButton.styleFrom(
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _markerAnimationController.dispose();
    _predictionTimer?.cancel();
    _freshnessTimer?.cancel();
    _autoFollowResumeTimer?.cancel();
    _locationSub?.cancel();
    _studentLocationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Tracking ${widget.busId}")),
      body: Column(
        children: [
          _buildStatusPanel(),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  key: const ValueKey('student_live_tracking_map'),
                  initialCameraPosition: CameraPosition(
                    target: _busPosition ?? _defaultMapCenter,
                    zoom: 15,
                  ),
                  markers: _buildMarkers(),
                  polylines: _buildPolylines(),
                  myLocationEnabled: _studentPosition != null,
                  myLocationButtonEnabled: true,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  padding: const EdgeInsets.only(bottom: 76),
                  onCameraMoveStarted: _handleCameraMoveStarted,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      unawaited(_fitTrackingBounds(force: true));
                    });
                  },
                ),
                _buildMapPlaceholder(),
                _buildAutoFollowControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _LiveMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Text(
              value,
              key: ValueKey(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
