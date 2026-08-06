import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:esec_bus/features/tracking/services/smartsync_driver_tracking_service.dart';
import 'package:esec_bus/smartsync/configuration/byzra_brand.dart';
import 'package:esec_bus/smartsync/modules/battery/location_power_profile.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  StreamSubscription<Position>? positionStream;
  Timer? powerPolicyTimer;
  Timer? serviceHeartbeatTimer;
  LocationPowerProfile? activePowerProfile;
  String? activeBusId;
  String? activeDriverId;
  var trackingRequested = false;
  var runtimeReady = false;
  Object? initializationError;

  void report(String event, Map<String, dynamic> details) {
    service.invoke(event, details);
  }

  Future<void> reportError(
    Object error, {
    String? busId,
    String? driverId,
    required String stage,
  }) async {
    report('trackingError', {
      'busId': busId,
      'driverId': driverId,
      'stage': stage,
      'message': error.toString(),
    });
  }

  LocationAccuracy accuracyFor(LocationPowerAccuracy accuracy) {
    return switch (accuracy) {
      LocationPowerAccuracy.high => LocationAccuracy.high,
      LocationPowerAccuracy.balanced => LocationAccuracy.medium,
      LocationPowerAccuracy.lowPower => LocationAccuracy.low,
    };
  }

  Future<void> startLocationStreamIfReady({bool reevaluate = false}) async {
    final busId = activeBusId;
    final driverId = activeDriverId;
    if (!trackingRequested ||
        !runtimeReady ||
        busId == null ||
        driverId == null) {
      return;
    }

    if (initializationError != null) {
      await reportError(
        initializationError,
        busId: busId,
        driverId: driverId,
        stage: 'initialization',
      );
      return;
    }

    final profile =
        await SmartSyncDriverTrackingService.currentLocationPowerProfile();
    if (positionStream != null &&
        (!reevaluate || profile == activePowerProfile)) {
      report('trackingStarted', {
        'busId': busId,
        'driverId': driverId,
        'alreadyRunning': true,
        'batteryMode': profile.batteryState.mode.name,
      });
      return;
    }

    await positionStream?.cancel();
    positionStream = null;
    activePowerProfile = profile;

    // ByZra controls the native request, not only the later Firestore decision.
    // This prevents the GPS chipset from staying at a fixed five-second,
    // high-accuracy cadence when Android Battery Saver or a low battery mode
    // requires a less expensive profile.
    final locationSettings = AndroidSettings(
      accuracy: accuracyFor(profile.accuracy),
      distanceFilter: profile.distanceFilterMeters,
      intervalDuration: profile.gpsInterval,
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            final currentBusId = activeBusId;
            final currentDriverId = activeDriverId;
            if (!trackingRequested ||
                currentBusId == null ||
                currentDriverId == null) {
              return;
            }

            try {
              final result =
                  await SmartSyncDriverTrackingService.syncDriverLocation(
                    busId: currentBusId,
                    driverId: currentDriverId,
                    latitude: position.latitude,
                    longitude: position.longitude,
                    speedMetersPerSecond: position.speed,
                    headingDegrees: position.heading,
                    accuracyMeters: position.accuracy,
                    capturedAt: position.timestamp,
                    source: 'background_service',
                  );
              report('trackingSyncResult', {
                'busId': currentBusId,
                'driverId': currentDriverId,
                'wroteLiveLocation': result.wroteLiveLocation,
                'queuedOffline': result.queuedOffline,
                'decision': result.decision.action.name,
                'reason': result.reason,
              });
            } catch (error) {
              await reportError(
                error,
                busId: currentBusId,
                driverId: currentDriverId,
                stage: 'sync',
              );
            }
          },
          onError: (Object error) {
            unawaited(
              reportError(
                error,
                busId: activeBusId,
                driverId: activeDriverId,
                stage: 'location_stream',
              ),
            );
          },
        );

    report('trackingStarted', {
      'busId': busId,
      'driverId': driverId,
      'alreadyRunning': false,
      'batteryMode': profile.batteryState.mode.name,
      'gpsIntervalSeconds': profile.gpsInterval.inSeconds,
      'distanceFilterMeters': profile.distanceFilterMeters,
      'accuracyPolicy': profile.accuracy.name,
    });

    Future<void> publishHeartbeat() async {
      final currentBusId = activeBusId;
      final currentDriverId = activeDriverId;
      if (!trackingRequested ||
          currentBusId == null ||
          currentDriverId == null) {
        return;
      }

      try {
        await SmartSyncDriverTrackingService.publishServiceHeartbeat(
          busId: currentBusId,
          driverId: currentDriverId,
        );
        report('trackingHeartbeat', {
          'busId': currentBusId,
          'driverId': currentDriverId,
          'connected': true,
        });
      } catch (error) {
        report('trackingHeartbeat', {
          'busId': currentBusId,
          'driverId': currentDriverId,
          'connected': false,
          'message': error.toString(),
        });
      }
    }

    await publishHeartbeat();
    serviceHeartbeatTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(publishHeartbeat());
    });
    powerPolicyTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (trackingRequested) {
        unawaited(startLocationStreamIfReady(reevaluate: true));
      }
    });
  }

  // Commands must be registered before any asynchronous initialization. The
  // platform command stream is broadcast-only, so registering later can lose
  // the first Start Trip command and leave tracking permanently disabled.
  service.on('startTracking').listen((event) {
    activeBusId = _readString(event, 'busId');
    activeDriverId = _readString(event, 'driverId');
    trackingRequested = activeBusId != null && activeDriverId != null;

    if (!trackingRequested) {
      unawaited(
        reportError(
          StateError('A busId and driverId are required to start tracking.'),
          stage: 'start_command',
        ),
      );
      return;
    }

    unawaited(startLocationStreamIfReady());
  });

  service.on('stopTracking').listen((event) async {
    final busId = activeBusId;
    final driverId = activeDriverId;

    trackingRequested = false;
    activeBusId = null;
    activeDriverId = null;
    activePowerProfile = null;
    serviceHeartbeatTimer?.cancel();
    serviceHeartbeatTimer = null;
    powerPolicyTimer?.cancel();
    powerPolicyTimer = null;
    await positionStream?.cancel();
    positionStream = null;

    if (busId == null || driverId == null) {
      report('trackingStopped', const {'alreadyStopped': true});
      service.stopSelf();
      return;
    }

    try {
      await SmartSyncDriverTrackingService.stopTrip(
        busId: busId,
        driverId: driverId,
      );
      report('trackingStopped', {'busId': busId, 'driverId': driverId});
    } catch (error) {
      await reportError(error, busId: busId, driverId: driverId, stage: 'stop');
    } finally {
      // Stop the foreground service after every trip. Leaving the isolate
      // running keeps Android's location foreground notification and service
      // alive even though Firestore already reports the trip as stopped.
      service.stopSelf();
    }
  });

  /// 🛑 Stop service properly
  service.on('stopService').listen((event) {
    serviceHeartbeatTimer?.cancel();
    powerPolicyTimer?.cancel();
    positionStream?.cancel();
    service.stopSelf();
  });

  // The UI waits for this acknowledgement before issuing startTracking. A
  // command received now is retained by the listener above until initialization
  // completes, then starts exactly one position stream.
  report('trackingReady', const {'state': 'command_channel_ready'});

  try {
    await Firebase.initializeApp();
    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();
      await service.setForegroundNotificationInfo(
        title: 'Bus Tracking Active',
        content: '${ByZraBrand.name} live tracking enabled',
      );
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is not granted.');
    }

    runtimeReady = true;
    await startLocationStreamIfReady();
  } catch (error) {
    initializationError = error;
    runtimeReady = true;
    if (trackingRequested) {
      await reportError(
        error,
        busId: activeBusId,
        driverId: activeDriverId,
        stage: 'initialization',
      );
    }
  }
}

String? _readString(Map<String, dynamic>? event, String key) {
  final value = event?[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return value.trim();
}
