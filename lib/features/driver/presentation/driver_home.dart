import 'dart:async';
import 'package:esec_bus/features/authentication/presentation/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:esec_bus/core/services/auth_service.dart';
import 'package:esec_bus/features/tracking/services/driver_tracking_service.dart';
import 'package:esec_bus/features/tracking/services/trip_start_validator.dart';
import 'package:esec_bus/core/services/session.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/shared/widgets/app_metric_tile.dart';
import 'package:esec_bus/shared/widgets/app_page_header.dart';
import 'package:esec_bus/shared/widgets/app_surface.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool _isLoadingAssignment = true;
  bool _isTripActionLoading = false;
  StreamSubscription<DriverTripState>? _tripStateSub;

  DriverBusAssignment? _assignedBus;
  DriverTripState _tripState = const DriverTripState(
    isRunning: false,
    status: "stopped",
  );
  String? _assignmentError;

  bool get isTripStarted => _tripState.isRunning;
  bool get _isTripControlledByAnotherDriver =>
      _tripState.isRunning &&
      _tripState.driverId != null &&
      _tripState.driverId != Session.userId;

  @override
  void initState() {
    super.initState();
    _loadAssignedBus();
  }

  Future<void> _loadAssignedBus() async {
    final driverId = Session.userId;
    if (driverId == null) {
      setState(() {
        _assignmentError = "Driver session not found";
        _isLoadingAssignment = false;
      });
      return;
    }

    try {
      setState(() {
        _assignmentError = null;
        _isLoadingAssignment = true;
      });

      final assignment = await DriverTrackingService.getAssignedBus(driverId);

      if (!mounted) return;

      if (assignment == null) {
        setState(() {
          _assignmentError = "No bus assigned to this driver";
          _isLoadingAssignment = false;
        });
        return;
      }

      // A new dashboard login always begins stopped. Clear any same-driver
      // state left behind by a terminated app before subscribing to updates.
      await _stopBackgroundTracking();
      await DriverTrackingService.prepareFreshDriverSession(
        busId: assignment.busId,
        driverId: driverId,
      );

      if (!mounted) return;

      setState(() {
        _assignedBus = assignment;
        _isLoadingAssignment = false;
      });

      _listenTripState(assignment.busId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assignmentError = "Unable to load assigned bus";
        _isLoadingAssignment = false;
      });
    }
  }

  void _listenTripState(String busId) {
    _tripStateSub?.cancel();
    _tripStateSub = DriverTrackingService.watchTripState(busId).listen((state) {
      if (!mounted) return;

      setState(() {
        _tripState = state;
      });
    });
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      final shouldOpenSettings = await _showGpsRequiredDialog();
      if (shouldOpenSettings == true) {
        await Geolocator.openLocationSettings();
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied")),
      );
      return false;
    }

    return true;
  }

  Future<bool> _sendCurrentLocation(
    Position position, {
    bool markTripStarted = false,
  }) async {
    final busId = _assignedBus?.busId;
    final driverId = Session.userId;

    if (busId == null || driverId == null) {
      throw StateError("Driver bus assignment is missing");
    }

    final result = await DriverTrackingService.updateLiveLocation(
      busId: busId,
      driverId: driverId,
      latitude: position.latitude,
      longitude: position.longitude,
      speedMetersPerSecond: position.speed,
      headingDegrees: position.heading,
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp,
      markTripStarted: markTripStarted,
    );

    debugPrint(
      "GPS Updated for $busId: ${position.latitude}, ${position.longitude}",
    );
    return result.wroteLiveLocation;
  }

  Future<void> _startTrip() async {
    final assignedBus = _assignedBus;
    if (assignedBus == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No assigned bus found")));
      return;
    }

    setState(() => _isTripActionLoading = true);

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) return;

      final isBusActive = await DriverTrackingService.isAssignedBusActive(
        assignedBus.busId,
      );
      if (!isBusActive) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Assigned bus is inactive")),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final validation = TripStartValidator().validate(
        bus: assignedBus.bus,
        driverId: Session.userId ?? '',
        currentLocation: LocationSample(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          capturedAt: position.timestamp,
        ),
      );
      if (!validation.canStart) {
        if (!mounted) return;
        _showTripStartValidationMessage(validation);
        return;
      }

      final locationWritten = await _sendCurrentLocation(
        position,
        markTripStarted: true,
      );
      if (!locationWritten) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Trip could not be activated. Check your network and try again.",
            ),
          ),
        );
        return;
      }
      final backgroundTrackingStarted = await _startBackgroundTracking(
        assignedBus.busId,
      );
      if (!backgroundTrackingStarted) {
        await _stopBackgroundTracking();
        await DriverTrackingService.stopTrip(
          busId: assignedBus.busId,
          driverId: Session.userId ?? '',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Live GPS service did not start. Please try starting the trip again.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_tripStartedMessage(validation))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unable to start trip: $e")));
    } finally {
      if (mounted) setState(() => _isTripActionLoading = false);
    }
  }

  void _showTripStartValidationMessage(TripStartValidationResult validation) {
    final message = switch (validation.status) {
      TripStartValidationStatus.assignmentMismatch =>
        "Your driver assignment does not match this bus. Contact the transport administrator.",
      TripStartValidationStatus.missingStartPoint =>
        "The assigned route's first stop has no GPS coordinates.",
      TripStartValidationStatus.invalidCurrentLocation =>
        "Unable to verify your current GPS location. Please try again.",
      TripStartValidationStatus.outsideStartRadius =>
        "Distance to ${validation.startStopName ?? 'the first stop'}: "
            "${_formatDistance(validation.distanceToStartMeters)}.",
      TripStartValidationStatus.eligible => "Trip is ready to start.",
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _tripStartedMessage(TripStartValidationResult validation) {
    return switch (validation.status) {
      TripStartValidationStatus.outsideStartRadius =>
        "Trip Started - Live GPS Enabled. "
            "${validation.startStopName ?? 'First stop'} is "
            "${_formatDistance(validation.distanceToStartMeters)} away.",
      TripStartValidationStatus.missingStartPoint =>
        "Trip Started - Live GPS Enabled. First-stop distance is not configured.",
      _ => "Trip Started - Live GPS Enabled",
    };
  }

  String _formatDistance(double? distanceMeters) {
    if (distanceMeters == null) return "unknown";
    if (distanceMeters < 1000) return "${distanceMeters.ceil()} m";
    return "${(distanceMeters / 1000).toStringAsFixed(2)} km";
  }

  Future<bool?> _showGpsRequiredDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Turn on GPS"),
          content: const Text(
            "Live bus tracking needs your phone GPS to be turned on before starting the trip.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
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

  Future<void> _stopTrip() async {
    if (_isTripControlledByAnotherDriver) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip is active from another driver")),
      );
      return;
    }

    setState(() => _isTripActionLoading = true);

    try {
      final busId = _assignedBus?.busId;
      final driverId = Session.userId;

      if (busId != null && driverId != null) {
        await DriverTrackingService.stopTrip(busId: busId, driverId: driverId);
        await _stopBackgroundTracking();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Trip Stopped")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unable to stop trip: $e")));
    } finally {
      if (mounted) setState(() => _isTripActionLoading = false);
    }
  }

  Future<void> _sendSos() async {
    final busId = _assignedBus?.busId;
    final driverId = Session.userId;
    if (busId == null || driverId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Send emergency SOS?"),
        content: const Text(
          "Your current location and assigned bus will be sent immediately.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Send SOS"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await DriverTrackingService.updateLiveLocation(
        busId: busId,
        driverId: driverId,
        latitude: position.latitude,
        longitude: position.longitude,
        speedMetersPerSecond: position.speed,
        headingDegrees: position.heading,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
        isEmergency: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Emergency SOS sent")));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unable to send SOS: $error")));
    }
  }

  Future<bool> _startBackgroundTracking(String busId) async {
    final driverId = Session.userId;
    if (driverId == null) return false;

    final service = FlutterBackgroundService();
    final commandReady = Completer<void>();
    final started = Completer<bool>();
    final failed = Completer<String>();

    late final StreamSubscription<Map<String, dynamic>?> readySub;
    late final StreamSubscription<Map<String, dynamic>?> startedSub;
    late final StreamSubscription<Map<String, dynamic>?> errorSub;

    readySub = service.on('trackingReady').listen((event) {
      if (!commandReady.isCompleted) commandReady.complete();
    });
    startedSub = service.on('trackingStarted').listen((event) {
      if (_backgroundEventMatches(event, busId, driverId) &&
          !started.isCompleted) {
        started.complete(true);
      }
    });
    errorSub = service.on('trackingError').listen((event) {
      if (_backgroundEventMatches(event, busId, driverId) &&
          !failed.isCompleted) {
        final message = event?['message'];
        failed.complete(
          message is String && message.isNotEmpty
              ? message
              : 'Live GPS service reported an unknown error.',
        );
      }
    });

    try {
      final isRunning = await service.isRunning();
      if (!isRunning) {
        final startedService = await service.startService();
        if (!startedService) {
          throw StateError('Unable to start the live GPS service.');
        }
        await commandReady.future.timeout(const Duration(seconds: 10));
      }

      // The background isolate has registered its command listener before it
      // sends trackingReady. This prevents the first command from being lost.
      service.invoke('startTracking', {'busId': busId, 'driverId': driverId});

      final acknowledged = await Future.any<bool>([
        started.future,
        failed.future.then<bool>((message) => throw StateError(message)),
      ]).timeout(const Duration(seconds: 15));
      return acknowledged;
    } catch (error) {
      debugPrint('Unable to start background tracking: $error');
      return false;
    } finally {
      await readySub.cancel();
      await startedSub.cancel();
      await errorSub.cancel();
    }
  }

  bool _backgroundEventMatches(
    Map<String, dynamic>? event,
    String busId,
    String driverId,
  ) {
    return event?['busId'] == busId && event?['driverId'] == driverId;
  }

  Future<void> _stopBackgroundTracking() async {
    final service = FlutterBackgroundService();
    service.invoke("stopTracking");
  }

  Future<void> _logout() async {
    if (isTripStarted) {
      await _stopTrip();
    }

    await AuthService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _tripStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Session.isDriver) {
      return const Scaffold(
        body: Center(
          child: Text("Unauthorized Access", style: TextStyle(fontSize: 16)),
        ),
      );
    }

    if (_isLoadingAssignment) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_assignmentError != null) {
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_bus, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  _assignmentError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadAssignedBus,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bus = _assignedBus;
    final busNo = bus?.busNo ?? "Bus";
    final routeName = bus?.routeName ?? "-";
    final routeNo = bus?.routeNo ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppPageHeader(
            title: "Trip Control",
            subtitle: "Start live GPS only when your assigned bus is ready.",
            icon: Icons.route_outlined,
            trailing: [
              StatusBadge(
                text: _tripStatusText(),
                color: isTripStarted ? Colors.white : Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSurface(
            child: Row(
              children: [
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.directions_bus_filled_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busNo,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$routeNo - $routeName",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppMetricTile(
                  label: "Trip",
                  value: _tripStatusText(),
                  icon: isTripStarted
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  color: isTripStarted ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppMetricTile(
                  label: "GPS",
                  value: isTripStarted ? "Active" : "Idle",
                  icon: Icons.gps_fixed_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isTripStarted ? Icons.radio_button_checked : Icons.circle,
                      color: isTripStarted ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isTripStarted
                            ? "Live GPS is being sent for your assigned bus."
                            : "Trip is stopped. Start only when the bus begins moving.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _isTripActionLoading
                        ? null
                        : _isTripControlledByAnotherDriver
                        ? null
                        : isTripStarted
                        ? _stopTrip
                        : _startTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTripStarted
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isTripActionLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isTripStarted ? "Stop Trip" : "Start Trip",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sendSos,
                    icon: const Icon(Icons.sos_rounded),
                    label: const Text("Emergency SOS"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isTripControlledByAnotherDriver
                      ? "This trip is controlled by another driver account."
                      : "Students assigned to this bus will see live updates after the trip starts.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tripStatusText() {
    if (_isTripControlledByAnotherDriver) return "Running by another driver";
    if (_tripState.status == "running") return "Running";
    if (_tripState.status == "stopped") return "Stopped";
    return "Not Started";
  }
}
