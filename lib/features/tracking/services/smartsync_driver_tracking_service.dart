import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:esec_bus/smartsync/services/runtime_battery_reader.dart';
import 'package:esec_bus/smartsync/storage/shared_preferences_offline_queue.dart';

class SmartSyncLocationSyncResult {
  final SyncDecision decision;
  final bool wroteLiveLocation;
  final bool queuedOffline;
  final String reason;

  const SmartSyncLocationSyncResult({
    required this.decision,
    required this.wroteLiveLocation,
    required this.queuedOffline,
    required this.reason,
  });
}

class SmartSyncRuntimeDependencies {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final SmartSyncConfig config;
  final RuntimeNetworkMonitor networkMonitor;
  final AdaptiveSynchronizationModule syncPlanner;
  final PacketOptimizationModule packetOptimizer;
  final MotionIntelligenceModule movementModule;
  final ReliableDeliveryModule deliveryModule;
  final SharedPreferencesOfflineQueue offlineQueue;
  final PowerOptimizationModule powerModule;
  final HealthMonitorModule healthMonitor;
  final MultiTransportModule transportModule;
  final CentralDecisionEngine decisionEngine;
  final PredictiveTrackingModule predictionModule;
  final RouteAwarenessModule routeModule;
  final SmartGeofenceModule geofenceModule;
  final EmergencyCommunicationModule emergencyModule;
  final SmartSyncAnalyticsModule analytics;
  final RuntimeBatteryReader batteryReader;

  const SmartSyncRuntimeDependencies({
    required this.firestore,
    required this.auth,
    required this.config,
    required this.networkMonitor,
    required this.syncPlanner,
    required this.packetOptimizer,
    required this.movementModule,
    required this.deliveryModule,
    required this.offlineQueue,
    required this.powerModule,
    required this.healthMonitor,
    required this.transportModule,
    required this.decisionEngine,
    required this.predictionModule,
    required this.routeModule,
    required this.geofenceModule,
    required this.emergencyModule,
    required this.analytics,
    required this.batteryReader,
  });

  factory SmartSyncRuntimeDependencies.production() {
    final config = SmartSyncConfig.defaults();
    return SmartSyncRuntimeDependencies(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      config: config,
      networkMonitor: RuntimeNetworkMonitor(),
      syncPlanner: AdaptiveSynchronizationModule(config: config),
      packetOptimizer: const PacketOptimizationModule(),
      movementModule: MotionIntelligenceModule.fromConfig(config),
      deliveryModule: ReliableDeliveryModule.fromConfig(config),
      offlineQueue: SharedPreferencesOfflineQueue.fromConfig(config),
      powerModule: PowerOptimizationModule.fromConfig(config),
      healthMonitor: const HealthMonitorModule(),
      transportModule: MultiTransportModule(),
      decisionEngine: CentralDecisionEngine.defaults(),
      predictionModule: PredictiveTrackingModule.fromConfig(config),
      routeModule: const RouteAwarenessModule(),
      geofenceModule: SmartGeofenceModule.fromConfig(config),
      emergencyModule: EmergencyCommunicationModule.fromConfig(config),
      analytics: SmartSyncAnalyticsModule(),
      batteryReader: RuntimeBatteryReader(),
    );
  }
}

class SmartSyncDriverTrackingService {
  static SmartSyncRuntimeDependencies _dependencies =
      SmartSyncRuntimeDependencies.production();

  static FirebaseFirestore get _firestore => _dependencies.firestore;
  static FirebaseAuth get _auth => _dependencies.auth;
  static SmartSyncConfig get _config => _dependencies.config;
  static RuntimeNetworkMonitor get _networkMonitor =>
      _dependencies.networkMonitor;
  static AdaptiveSynchronizationModule get _syncPlanner =>
      _dependencies.syncPlanner;
  static PacketOptimizationModule get _packetOptimizer =>
      _dependencies.packetOptimizer;
  static MotionIntelligenceModule get _movementModule =>
      _dependencies.movementModule;
  static ReliableDeliveryModule get _deliveryModule =>
      _dependencies.deliveryModule;
  static SharedPreferencesOfflineQueue get _offlineQueue =>
      _dependencies.offlineQueue;
  static PowerOptimizationModule get _powerModule => _dependencies.powerModule;
  static HealthMonitorModule get _healthMonitor => _dependencies.healthMonitor;
  static MultiTransportModule get _transportModule =>
      _dependencies.transportModule;
  static CentralDecisionEngine get _decisionEngine =>
      _dependencies.decisionEngine;
  static PredictiveTrackingModule get _predictionModule =>
      _dependencies.predictionModule;
  static RouteAwarenessModule get _routeModule => _dependencies.routeModule;
  static SmartGeofenceModule get _geofenceModule =>
      _dependencies.geofenceModule;
  static EmergencyCommunicationModule get _emergencyModule =>
      _dependencies.emergencyModule;
  static SmartSyncAnalyticsModule get _analytics => _dependencies.analytics;
  static RuntimeBatteryReader get _batteryReader => _dependencies.batteryReader;

  static LocationSample? _previousSample;
  static LocationSample? _lastAcceptedSample;
  static DateTime? _lastSyncedAt;
  static int _retryCount = 0;
  static final List<LocationSample> _locationHistory = [];
  static final List<Map<String, Object?>> _runtimeSamples = [];
  static LocationPowerProfile? _locationPowerProfile;
  static int _acceptedSamples = 0;
  static int _rejectedSamples = 0;
  static int _packetsSent = 0;
  static int _packetsDropped = 0;
  static int _lastWriteDurationMs = 0;
  static int _powerSavingEvents = 0;
  static double _distanceTravelledMeters = 0;
  static BatteryMode? _lastBatteryMode;

  @visibleForTesting
  static void configureDependencies(SmartSyncRuntimeDependencies dependencies) {
    _dependencies = dependencies;
    _previousSample = null;
    _lastAcceptedSample = null;
    _lastSyncedAt = null;
    _retryCount = 0;
    _locationHistory.clear();
    _runtimeSamples.clear();
    _locationPowerProfile = null;
    _acceptedSamples = 0;
    _rejectedSamples = 0;
    _packetsSent = 0;
    _packetsDropped = 0;
    _lastWriteDurationMs = 0;
    _powerSavingEvents = 0;
    _distanceTravelledMeters = 0;
    _lastBatteryMode = null;
  }

  static Future<LocationPowerProfile> currentLocationPowerProfile() async {
    final reading =
        await _batteryReader.read() ??
        BatteryReading(
          levelPercent: 100,
          isCharging: true,
          measuredAt: DateTime.now(),
        );
    final profile = _powerModule.locationProfile(reading: reading);
    _locationPowerProfile = profile;
    return profile;
  }

  static Future<void> publishServiceHeartbeat({
    required String busId,
    required String driverId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != driverId) {
      throw StateError('Authenticated driver identity is required');
    }

    await _firestore.collection(FirestoreCollections.buses).doc(busId).update({
      'tracking.serviceHeartbeatAt': FieldValue.serverTimestamp(),
      'tracking.smartSync.engine': ByZraBrand.name,
      'tracking.smartSync.serviceConnected': true,
    });
  }

  static Future<SmartSyncLocationSyncResult> syncDriverLocation({
    required String busId,
    required String driverId,
    required double latitude,
    required double longitude,
    double? speedMetersPerSecond,
    double? headingDegrees,
    double? accuracyMeters,
    DateTime? capturedAt,
    bool markTripStarted = false,
    bool isEmergency = false,
    String source = 'driver_app',
  }) async {
    final now = DateTime.now();
    final sample = LocationSample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: speedMetersPerSecond,
      headingDegrees: headingDegrees,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt ?? now,
    );
    final packet = _packetFor(
      busId: busId,
      driverId: driverId,
      sample: sample,
      source: source,
    );

    final network = await _networkMonitor.refresh();
    final batterySnapshot = await _batteryState();
    final batteryState = batterySnapshot.state;
    final movementState = _movementStateFor(sample);
    final healthStatus = await _healthStatusFor(
      sample: sample,
      networkStatus: network,
    );
    final offlineQueueSize = await _offlineQueue.size();
    final transportValidation = _transportModule.validatePacket(
      packet: packet,
      type: _config.transportType,
      now: now,
    );

    final schedule = _syncPlanner.plan(
      networkStatus: network,
      now: now,
      lastSyncedAt: _lastSyncedAt,
      isEmergency: isEmergency,
    );

    final route = await _loadRoute(busId);
    final routeProgress = route == null
        ? null
        : _routeModule.analyze(
            route: route,
            currentLocation: sample,
            previousLocation: _previousSample,
          );
    final geofenceResult = _geofenceModule.evaluate(
      geofences: route == null ? const [] : _geofencesFor(route),
      currentLocation: sample,
      previousLocation: _previousSample,
    );
    final prediction = _predictionModule.predict(
      PredictionInput(
        previousGps: _lastAcceptedSample ?? sample,
        predictionTime: sample.capturedAt,
        hasLiveGps: !network.isOffline,
        historicalMovement: List.unmodifiable(_locationHistory),
        distanceToDestinationMeters: routeProgress?.distanceRemainingMeters,
      ),
    );

    if (isEmergency) {
      _emergencyModule.handle(
        EmergencyEvent(
          eventId: packet.packetId,
          deviceId: driverId,
          transportId: busId,
          triggerType: EmergencyTriggerType.sos,
          triggeredAt: now,
          location: sample,
        ),
      );
    }

    final decision = _decisionEngine.decide(
      SmartSyncDecisionContext(
        sample: sample,
        networkStatus: network,
        batteryState: batteryState,
        movementState: movementState,
        healthStatus: healthStatus,
        offlineQueueSize: offlineQueueSize,
        retryCount: _retryCount,
        isEmergency: isEmergency,
        transportIsValid: transportValidation.isValid,
        transportWarning: transportValidation.warnings.join(', '),
        synchronizationDue: markTripStarted || schedule.shouldSyncNow,
        synchronizationDelay:
            schedule.nextSyncAt?.difference(now) ?? schedule.interval,
      ),
    );
    if (decision.action == SyncAction.drop) _packetsDropped++;
    if (_lastBatteryMode != batteryState.mode &&
        (batteryState.mode == BatteryMode.powerSaving ||
            batteryState.mode == BatteryMode.emergencySaving)) {
      _powerSavingEvents++;
    }
    _lastBatteryMode = batteryState.mode;

    _analytics.record('decision.${decision.action.name}', {
      'busId': busId,
      'driverId': driverId,
      'reason': decision.reason,
      'source': source,
    });
    await _publishRuntime(
      busId: busId,
      driverId: driverId,
      sample: sample,
      network: network,
      battery: batteryState,
      movement: movementState,
      health: healthStatus,
      decision: decision,
      syncInterval: schedule.interval,
      offlineQueueSize: offlineQueueSize,
      routeProgress: routeProgress,
      geofenceResult: geofenceResult,
      prediction: prediction,
      packet: packet,
      batteryReadingAvailable: batterySnapshot.isRuntimeReading,
    );

    switch (decision.action) {
      case SyncAction.sendNow:
      case SyncAction.emergencySend:
        final result = await _writeWithRetry(
          packet: packet,
          busId: busId,
          driverId: driverId,
          source: source,
          decision: decision,
          markTripStarted: markTripStarted,
        );
        _rememberSample(sample, accepted: result.wroteLiveLocation);
        return result;
      case SyncAction.queueOffline:
        await _offlineQueue.enqueue(packet);
        _rememberSample(sample, accepted: false);
        return SmartSyncLocationSyncResult(
          decision: decision,
          wroteLiveLocation: false,
          queuedOffline: true,
          reason: decision.reason,
        );
      case SyncAction.wait:
      case SyncAction.retry:
      case SyncAction.drop:
      case SyncAction.predict:
        _rememberSample(sample, accepted: false);
        return SmartSyncLocationSyncResult(
          decision: decision,
          wroteLiveLocation: false,
          queuedOffline: false,
          reason: decision.reason,
        );
    }
  }

  static Future<void> stopTrip({
    required String busId,
    required String driverId,
  }) async {
    _previousSample = null;
    _lastAcceptedSample = null;
    _lastSyncedAt = null;
    _retryCount = 0;
    _locationHistory.clear();
    _runtimeSamples.clear();
    _acceptedSamples = 0;
    _rejectedSamples = 0;
    _packetsSent = 0;
    _packetsDropped = 0;
    _lastWriteDurationMs = 0;
    _powerSavingEvents = 0;
    _distanceTravelledMeters = 0;
    _lastBatteryMode = null;

    await _firestore.collection(FirestoreCollections.buses).doc(busId).update({
      'tracking.busId': busId,
      'tracking.driverId': driverId,
      'tracking.isActive': false,
      'tracking.status': 'stopped',
      'tracking.tripStoppedAt': FieldValue.serverTimestamp(),
      'tracking.serviceHeartbeatAt': FieldValue.delete(),
      'tracking.lastUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tracking.smartSync': {
        'engine': ByZraBrand.name,
        'decision': 'stop_trip',
        'queuedOffline': false,
      },
    });
  }

  static Future<void> flushOfflineQueue() async {
    final pending = await _offlineQueue.readItems(limit: 20);
    if (pending.isEmpty) return;

    final network = await _networkMonitor.refresh();
    if (network.isOffline) return;

    for (final item in pending) {
      final busId = item.packet.transportId;
      final driverId = item.packet.deviceId;
      await _offlineQueue.markSyncing(item.packetId);
      try {
        await _writePacket(
          packet: item.packet,
          busId: busId,
          driverId: driverId,
          source:
              (item.packet.metadata['source'] as String?) ?? 'offline_queue',
          decision: const SyncDecision.sendNow(reason: 'offline_queue_flush'),
          markTripStarted: false,
        );
        await _offlineQueue.markSynced(item.packetId);
      } on Object catch (error) {
        await _offlineQueue.markFailed(item.packetId, error.toString());
      }
    }

    await _offlineQueue.cleanup();
  }

  static SyncPacket _packetFor({
    required String busId,
    required String driverId,
    required LocationSample sample,
    required String source,
  }) {
    return SyncPacket(
      packetId: '$busId-${sample.capturedAt.microsecondsSinceEpoch}',
      deviceId: driverId,
      transportId: busId,
      sample: sample,
      metadata: {'source': source, 'app': 'BusBuddy'},
    );
  }

  static MovementState _movementStateFor(LocationSample sample) {
    final previous = _previousSample;
    if (previous == null) {
      return MovementState(
        type: MovementType.moving,
        distanceSinceLastSyncMeters: _config.movementThresholdMeters,
        lastAcceptedSample: sample,
      );
    }

    return _movementModule
        .analyzeMovement(
          previous: previous,
          current: sample,
          lastAcceptedSample: _lastAcceptedSample,
        )
        .state;
  }

  static Future<({BatteryState state, bool isRuntimeReading})>
  _batteryState() async {
    final reading = await _batteryReader.read();
    if (reading != null) {
      return (state: _powerModule.classify(reading), isRuntimeReading: true);
    }

    return (
      state: const BatteryState(
        levelPercent: 100,
        isCharging: true,
        mode: BatteryMode.normal,
      ),
      isRuntimeReading: false,
    );
  }

  static Future<HealthStatus> _healthStatusFor({
    required LocationSample sample,
    required NetworkStatus networkStatus,
  }) async {
    final checks = <HealthCheckResult>[
      sample.hasValidCoordinates
          ? HealthCheckResult.healthy(component: 'gps')
          : HealthCheckResult.unhealthy(
              component: 'gps',
              severity: HealthSeverity.critical,
              warning: 'GPS coordinates are invalid.',
              recoverySuggestion: 'Wait for an accurate GPS fix.',
            ),
      networkStatus.isOffline
          ? HealthCheckResult.unhealthy(
              component: 'network',
              severity: HealthSeverity.warning,
              warning: 'Network is offline.',
              recoverySuggestion: 'Queue updates until network is available.',
            )
          : HealthCheckResult.healthy(component: 'network'),
    ];

    final accuracy = sample.accuracyMeters;
    if (accuracy != null && accuracy > 80) {
      checks.add(
        HealthCheckResult.unhealthy(
          component: 'gps_accuracy',
          severity: HealthSeverity.warning,
          warning: 'GPS accuracy is low.',
          recoverySuggestion: 'Keep the device near a clear GPS signal.',
          metadata: {'accuracyMeters': accuracy},
        ),
      );
    }

    return _healthMonitor.evaluate(checks);
  }

  static Future<SmartSyncLocationSyncResult> _writeWithRetry({
    required SyncPacket packet,
    required String busId,
    required String driverId,
    required String source,
    required SyncDecision decision,
    required bool markTripStarted,
  }) async {
    var retryCount = _retryCount;
    final stopwatch = Stopwatch()..start();

    while (true) {
      try {
        await _writePacket(
          packet: packet,
          busId: busId,
          driverId: driverId,
          source: source,
          decision: decision,
          markTripStarted: markTripStarted,
        );
        _retryCount = 0;
        _lastSyncedAt = DateTime.now();
        stopwatch.stop();
        _lastWriteDurationMs = stopwatch.elapsedMilliseconds;
        _packetsSent++;
        await flushOfflineQueue();
        return SmartSyncLocationSyncResult(
          decision: decision,
          wroteLiveLocation: true,
          queuedOffline: false,
          reason: decision.reason,
        );
      } on Object catch (error) {
        final network = await _networkMonitor.currentStatus();
        final retryDecision = _deliveryModule.decide(
          result: SyncResult(
            success: false,
            statusCode: 0,
            completedAt: DateTime.now(),
            message: error.toString(),
          ),
          networkStatus: network,
          currentRetryCount: retryCount,
        );

        if (retryDecision.shouldRetry) {
          retryCount = retryDecision.nextRetryCount;
          _retryCount = retryCount;
          await Future<void>.delayed(retryDecision.retryDelay);
          continue;
        }

        if (retryDecision.shouldQueueOffline) {
          await _offlineQueue.enqueue(packet);
          return SmartSyncLocationSyncResult(
            decision: const SyncDecision.queueOffline(
              reason: 'delivery failed, queued offline',
            ),
            wroteLiveLocation: false,
            queuedOffline: true,
            reason: retryDecision.reason,
          );
        }

        debugPrint(
          '${ByZraBrand.name} dropped packet ${packet.packetId}: $error',
        );
        stopwatch.stop();
        _lastWriteDurationMs = stopwatch.elapsedMilliseconds;
        _packetsDropped++;
        return SmartSyncLocationSyncResult(
          decision: SyncDecision.drop(reason: retryDecision.reason),
          wroteLiveLocation: false,
          queuedOffline: false,
          reason: retryDecision.reason,
        );
      }
    }
  }

  static Future<void> _writePacket({
    required SyncPacket packet,
    required String busId,
    required String driverId,
    required String source,
    required SyncDecision decision,
    required bool markTripStarted,
  }) async {
    final optimized = _packetOptimizer.optimize(packet);
    final security = await _securityMetadata(packet, driverId);
    final sample = packet.sample;
    final payload = <String, dynamic>{
      'tracking.busId': busId,
      'tracking.driverId': driverId,
      'tracking.currentPoint.latitude': sample.latitude,
      'tracking.currentPoint.longitude': sample.longitude,
      if (sample.speedMetersPerSecond != null)
        'tracking.currentPoint.speed': sample.speedMetersPerSecond,
      if (sample.headingDegrees != null)
        'tracking.currentPoint.heading': sample.headingDegrees,
      if (sample.accuracyMeters != null)
        'tracking.currentPoint.accuracy': sample.accuracyMeters,
      'tracking.currentPoint.capturedAt': Timestamp.fromDate(sample.capturedAt),
      if (markTripStarted) 'tracking.isActive': true,
      if (markTripStarted) 'tracking.status': 'running',
      if (markTripStarted)
        'tracking.serviceHeartbeatAt': FieldValue.serverTimestamp(),
      'tracking.source': source,
      'tracking.lastUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tracking.smartSync': {
        'engine': ByZraBrand.name,
        'packetId': packet.packetId,
        'decision': decision.action.name,
        'reason': decision.reason,
        'compressed': optimized.isCompact,
        'estimatedBytes': optimized.estimatedBytes,
        'security': security,
      },
    };

    if (markTripStarted) {
      payload['tracking.tripStartedAt'] = FieldValue.serverTimestamp();
    }

    await _firestore
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .update(payload);

    if (decision.isEmergency) {
      await _firestore
          .collection(FirestoreCollections.emergencies)
          .doc(packet.packetId)
          .set({
            'eventId': packet.packetId,
            'busId': busId,
            'driverId': driverId,
            'type': 'sos',
            'priority': 'critical',
            'status': 'active',
            'acknowledged': false,
            'cleared': false,
            'location': {
              'latitude': sample.latitude,
              'longitude': sample.longitude,
              'capturedAt': Timestamp.fromDate(sample.capturedAt),
            },
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    }
  }

  static void _rememberSample(LocationSample sample, {required bool accepted}) {
    _previousSample = sample;
    _locationHistory.add(sample);
    if (_locationHistory.length > 20) _locationHistory.removeAt(0);
    if (accepted) {
      final previousAccepted = _lastAcceptedSample;
      if (previousAccepted != null) {
        _distanceTravelledMeters += GeoDistance.metersBetween(
          previousAccepted,
          sample,
        );
      }
      _acceptedSamples++;
      _lastAcceptedSample = sample;
    } else {
      _rejectedSamples++;
    }
  }

  static Future<Map<String, Object?>> _securityMetadata(
    SyncPacket packet,
    String driverId,
  ) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null || user.uid != driverId || token == null) {
      throw StateError('Authenticated driver identity is required');
    }

    final security = SecurityModule(
      trustedDeviceIds: {driverId},
      validTokens: {token},
    );
    final request = security.sign(
      packet: packet,
      credentials: SecurityCredentials(
        deviceId: driverId,
        token: token,
        signingKeyId: 'firebase-auth-v1',
      ),
      nonce: packet.packetId,
    );
    final validation = security.validate(request);
    if (!validation.isValid) {
      throw StateError(
        '${ByZraBrand.name} security rejected: ${validation.reason}',
      );
    }

    return {
      'signature': request.signature,
      'nonce': request.nonce,
      'signingKeyId': request.signingKeyId,
      'timestamp': request.timestamp.toIso8601String(),
      'validated': true,
    };
  }

  static Future<RouteDefinition?> _loadRoute(String busId) async {
    final bus = await _firestore
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .get();
    final route = firestoreMap(bus.data()?['route']);
    final points = route['trackPoints'];
    if (points is! List) return null;

    final stops = <RouteStop>[];
    for (var index = 0; index < points.length; index++) {
      final point = firestoreMap(points[index]);
      final latitude = firestoreDouble(point['latitude']);
      final longitude = firestoreDouble(point['longitude']);
      if (latitude == null || longitude == null) continue;
      final name = firestoreString(point['name']) ?? 'Stop ${index + 1}';
      stops.add(
        RouteStop(
          stopId: firestoreString(point['stopId']) ?? '$busId-$index',
          name: name,
          sequence: point['sequence'] is int ? point['sequence'] as int : index,
          location: LocationSample(
            latitude: latitude,
            longitude: longitude,
            capturedAt: DateTime.now(),
          ),
        ),
      );
    }
    if (stops.length < 2) return null;

    return RouteDefinition(
      routeId: firestoreString(route['routeId']) ?? busId,
      routeName: firestoreString(route['routeName']) ?? busId,
      stops: stops,
    );
  }

  static List<GeofenceDefinition> _geofencesFor(RouteDefinition route) {
    return route.stops
        .map(
          (stop) => GeofenceDefinition(
            geofenceId: stop.stopId,
            name: stop.name,
            type: GeofenceType.busStop,
            center: stop.location,
            radiusMeters: _config.geofenceRadiusMeters,
            metadata: {'routeId': route.routeId},
          ),
        )
        .toList(growable: false);
  }

  static Future<void> _publishRuntime({
    required String busId,
    required String driverId,
    required LocationSample sample,
    required NetworkStatus network,
    required BatteryState battery,
    required MovementState movement,
    required HealthStatus health,
    required SyncDecision decision,
    required Duration syncInterval,
    required int offlineQueueSize,
    required RouteProgress? routeProgress,
    required GeofenceEvaluationResult geofenceResult,
    required PredictionResult prediction,
    required SyncPacket packet,
    required bool batteryReadingAvailable,
  }) async {
    try {
      final optimized = _packetOptimizer.optimize(packet);
      final original = const PacketOptimizationModule(
        rules: PacketOptimizationRules.compatible(),
      ).optimize(packet);
      final savedBytes = (original.estimatedBytes - optimized.estimatedBytes)
          .clamp(0, original.estimatedBytes);
      final compressionPercent = original.estimatedBytes == 0
          ? 0.0
          : savedBytes / original.estimatedBytes * 100;
      final runtimeMetrics = <String, Object?>{
        'speedMetersPerSecond': sample.speedMetersPerSecond,
        'distanceTravelledMeters': _distanceTravelledMeters,
        'acceptedSamples': _acceptedSamples,
        'rejectedSamples': _rejectedSamples,
        'packetOriginalBytes': original.estimatedBytes,
        'packetCompressedBytes': optimized.estimatedBytes,
        'compressionPercent': compressionPercent,
        'savedBandwidthBytes': savedBytes,
        'packetsSent': _packetsSent,
        'packetsDropped': _packetsDropped,
        'actualSyncTimeMs': _lastWriteDurationMs,
        'powerSavingEvents': _powerSavingEvents,
        'healthWarnings': health.warnings,
        'predictionReason': prediction.reason,
      };
      final samplePoint = <String, Object?>{
        'recordedAt': sample.capturedAt.toIso8601String(),
        'batteryLevel': battery.levelPercent,
        'latencyMs': network.latency.inMilliseconds,
        'packetLossPercent': network.packetLossPercent,
        'signalStability': network.signalStability,
        'gpsAccuracyMeters': sample.accuracyMeters,
        'syncIntervalSeconds': syncInterval.inSeconds,
        'actualSyncTimeMs': _lastWriteDurationMs,
        'speedMetersPerSecond': sample.speedMetersPerSecond,
        'healthScore': health.score,
        'predictionConfidence': prediction.confidenceScore,
        'retryCount': _retryCount,
        'offlineQueueSize': offlineQueueSize,
        'packetOriginalBytes': original.estimatedBytes,
        'packetCompressedBytes': optimized.estimatedBytes,
      };
      _runtimeSamples.add(samplePoint);
      if (_runtimeSamples.length > 30) _runtimeSamples.removeAt(0);
      final executionTime = sample.capturedAt.toIso8601String();
      Map<String, Object?> module(
        String status,
        String currentDecision,
        Object values, {
        int? healthScore,
      }) => {
        'status': status,
        'decision': currentDecision,
        'values': values,
        'lastExecutionAt': executionTime,
        'health': healthScore ?? health.score,
      };
      final modules = <String, Object?>{
        'Network Intelligence': module(
          network.isOffline ? 'waiting' : 'running',
          network.quality.name,
          {
            'latencyMs': network.latency.inMilliseconds,
            'packetLossPercent': network.packetLossPercent,
            'signalStability': network.signalStability,
          },
        ),
        'Adaptive Synchronization': module(
          decision.action == SyncAction.wait ? 'waiting' : 'running',
          decision.action.name,
          {'intervalSeconds': syncInterval.inSeconds},
        ),
        'Packet Optimization': module('running', 'optimized', {
          'originalBytes': original.estimatedBytes,
          'compressedBytes': optimized.estimatedBytes,
          'savedBytes': savedBytes,
        }),
        'Motion Intelligence': module('running', movement.type.name, {
          'distanceMeters': movement.distanceSinceLastSyncMeters,
          'speedMetersPerSecond': sample.speedMetersPerSecond,
        }),
        'Reliable Delivery': module(
          _retryCount > 0 ? 'waiting' : 'running',
          _retryCount > 0 ? 'retrying' : 'ready',
          {'retryCount': _retryCount},
        ),
        'Offline Queue': module(
          offlineQueueSize > 0 ? 'waiting' : 'running',
          offlineQueueSize > 0 ? 'queued' : 'empty',
          {'queueSize': offlineQueueSize},
        ),
        'Battery Optimization': module('running', battery.mode.name, {
          'batteryLevel': battery.levelPercent,
          'systemPowerSaver': battery.isPowerSaveMode,
        }),
        'Emergency Communication': module(
          decision.isEmergency ? 'running' : 'waiting',
          decision.isEmergency ? 'emergencySync' : 'armed',
          {'priorityEnabled': _config.emergencyPriorityEnabled},
        ),
        'Predictive Tracking': module(
          prediction.isActive ? 'running' : 'waiting',
          prediction.reason,
          {'confidence': prediction.confidenceScore},
        ),
        'Route Awareness': module(
          routeProgress == null ? 'waiting' : 'running',
          routeProgress?.status.name ?? 'routeUnavailable',
          {'completedPercent': routeProgress?.routeCompletedPercent},
        ),
        'Smart Geofence': module(
          routeProgress == null ? 'waiting' : 'running',
          geofenceResult.events.isEmpty ? 'monitoring' : 'event',
          {
            'events': geofenceResult.events
                .map((event) => event.eventType.name)
                .toList(growable: false),
          },
        ),
        'Security': module(
          decision.action == SyncAction.sendNow || decision.isEmergency
              ? 'running'
              : 'waiting',
          'identityValidation',
          {'authenticatedDriver': _auth.currentUser?.uid == driverId},
        ),
        'Health Monitor': module(
          health.severity == HealthSeverity.critical ? 'error' : 'running',
          health.severity.name,
          {'warnings': health.warnings},
          healthScore: health.score,
        ),
        'Multi Transport Validation': module(
          'running',
          _config.transportType.name,
          {'transportType': _config.transportType.name},
        ),
        'Central Decision Engine': module('running', decision.action.name, {
          'reason': decision.reason,
        }),
      };
      await _firestore
          .collection(FirestoreCollections.smartSyncRuntime)
          .doc(busId)
          .set({
            'busId': busId,
            'driverId': driverId,
            'networkQuality': network.quality.name,
            'latencyMs': network.latency.inMilliseconds,
            'packetLossPercent': network.packetLossPercent,
            'signalStability': network.signalStability,
            'gpsAccuracyMeters': sample.accuracyMeters,
            'syncIntervalSeconds': syncInterval.inSeconds,
            'decision': decision.action.name,
            'decisionReason': decision.reason,
            'movementStatus': movement.type.name,
            'retryCount': _retryCount,
            'offlineQueueSize': offlineQueueSize,
            'batteryMode': battery.mode.name,
            'batteryLevel': battery.levelPercent,
            'batteryReadingAvailable': batteryReadingAvailable,
            'systemPowerSaver': battery.isPowerSaveMode,
            if (_locationPowerProfile case final profile?)
              'gpsPowerPolicy': {
                'accuracy': profile.accuracy.name,
                'intervalSeconds': profile.gpsInterval.inSeconds,
                'distanceFilterMeters': profile.distanceFilterMeters,
                'reason': profile.reason,
              },
            'routeStatus': routeProgress?.status.name ?? 'unavailable',
            'routeCompletedPercent': routeProgress?.routeCompletedPercent ?? 0,
            'geofenceEvents': geofenceResult.events
                .map((event) => event.eventType.name)
                .toList(growable: false),
            'healthScore': health.score,
            'healthSeverity': health.severity.name,
            'predictionActive': prediction.isActive,
            'predictionConfidence': prediction.confidenceScore,
            'runtimeMetrics': runtimeMetrics,
            'runtimeSamples': List<Map<String, Object?>>.unmodifiable(
              _runtimeSamples,
            ),
            'modules': modules,
            'activeModules': const [
              'network',
              'synchronization',
              'packet',
              'movement',
              'retry',
              'offline',
              'prediction',
              'battery',
              'emergency',
              'route',
              'geofence',
              'security',
              'health',
              'transport',
              'analytics',
            ],
            'eventCounts': _analytics.eventCounts,
            'recentEvents': _analytics.recentEvents.take(10).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      debugPrint('${ByZraBrand.name} runtime telemetry failed: ${error.code}');
    }
  }
}
