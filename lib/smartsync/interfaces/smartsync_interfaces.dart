import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/models/battery_state.dart';
import 'package:esec_bus/smartsync/models/health_status.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/models/movement_state.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/sync_decision.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/models/sync_result.dart';
import 'package:esec_bus/smartsync/modules/battery/battery_reading.dart';
import 'package:esec_bus/smartsync/modules/battery/location_power_profile.dart';
import 'package:esec_bus/smartsync/modules/battery/power_optimization_result.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_event.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_sync_result.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_definition.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_evaluation_result.dart';
import 'package:esec_bus/smartsync/modules/packet/optimized_sync_payload.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_item.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_stats.dart';
import 'package:esec_bus/smartsync/modules/retry/delivery_failure_type.dart';
import 'package:esec_bus/smartsync/modules/retry/delivery_retry_decision.dart';
import 'package:esec_bus/smartsync/modules/prediction/prediction_input.dart';
import 'package:esec_bus/smartsync/modules/prediction/prediction_result.dart';
import 'package:esec_bus/smartsync/modules/route/route_definition.dart';
import 'package:esec_bus/smartsync/modules/route/route_progress.dart';
import 'package:esec_bus/smartsync/modules/security/security_credentials.dart';
import 'package:esec_bus/smartsync/modules/security/security_validation_result.dart';
import 'package:esec_bus/smartsync/modules/security/signed_sync_request.dart';
import 'package:esec_bus/smartsync/modules/synchronization/sync_schedule.dart';

abstract interface class SmartSyncConfigurationProvider {
  SmartSyncConfig currentConfig();
}

abstract interface class SmartSyncGpsProvider {
  Stream<LocationSample> watchLocation();
}

abstract interface class SmartSyncNetworkMonitor {
  Stream<NetworkStatus> watchNetwork();
  Future<NetworkStatus> currentStatus();
}

abstract interface class SmartSyncDecisionEngine {
  SyncDecision decide(SmartSyncDecisionContext context);
}

abstract interface class SmartSyncSynchronizationPlanner {
  Duration intervalFor(NetworkStatus networkStatus);

  SyncSchedule plan({
    required NetworkStatus networkStatus,
    required DateTime now,
    DateTime? lastSyncedAt,
    bool isEmergency = false,
  });
}

abstract interface class SmartSyncPacketOptimizer {
  OptimizedSyncPayload optimize(SyncPacket packet);
}

abstract interface class SmartSyncMovementAnalyzer {
  MovementState analyze(LocationSample previous, LocationSample current);
}

abstract interface class SmartSyncTransport {
  Future<SyncResult> send(SyncPacket packet);
}

abstract interface class SmartSyncReliableDeliveryPlanner {
  DeliveryRetryDecision decide({
    required SyncResult result,
    required NetworkStatus networkStatus,
    required int currentRetryCount,
  });

  DeliveryFailureType classifyFailure(SyncResult result);
}

abstract interface class SmartSyncOfflineQueue {
  Future<void> enqueue(SyncPacket packet);
  Future<OfflineQueueItem> enqueueItem(SyncPacket packet);
  Future<List<SyncPacket>> readBatch({required int limit});
  Future<List<OfflineQueueItem>> readItems({required int limit});
  Future<void> markSyncing(String packetId);
  Future<void> markSynced(String packetId);
  Future<void> markFailed(String packetId, String error);
  Future<void> requeueFailed(String packetId);
  Future<void> cleanup();
  Future<int> size();
  Future<OfflineQueueStats> stats();
}

abstract interface class SmartSyncPredictionEngine {
  PredictionResult predict(PredictionInput input);
}

abstract interface class SmartSyncPowerOptimizer {
  BatteryState classify(BatteryReading reading);

  LocationPowerProfile locationProfile({
    required BatteryReading reading,
    Duration baseGpsInterval = const Duration(seconds: 8),
    int baseDistanceFilterMeters = 20,
  });

  PowerOptimizationResult optimize({
    required BatteryReading reading,
    required Duration baseSyncInterval,
    required Duration baseGpsInterval,
  });
}

abstract interface class SmartSyncEmergencyCoordinator {
  EmergencySyncResult handle(EmergencyEvent event);
}

abstract interface class SmartSyncRouteAnalyzer {
  RouteProgress analyze({
    required RouteDefinition route,
    required LocationSample currentLocation,
    LocationSample? previousLocation,
  });
}

abstract interface class SmartSyncGeofenceEvaluator {
  GeofenceEvaluationResult evaluate({
    required List<GeofenceDefinition> geofences,
    required LocationSample currentLocation,
    LocationSample? previousLocation,
  });
}

abstract interface class SmartSyncSecurityManager {
  SignedSyncRequest sign({
    required SyncPacket packet,
    required SecurityCredentials credentials,
    required String nonce,
    DateTime? timestamp,
  });

  SecurityValidationResult validate(SignedSyncRequest request);
}

abstract interface class SmartSyncTelemetrySink {
  void record(String eventName, Map<String, Object?> data);
}

abstract interface class SmartSyncHealthMonitor {
  Future<HealthStatus> checkHealth();
}

class SmartSyncDecisionContext {
  final LocationSample sample;
  final NetworkStatus networkStatus;
  final BatteryState batteryState;
  final MovementState movementState;
  final HealthStatus healthStatus;
  final int offlineQueueSize;
  final int retryCount;
  final bool isEmergency;
  final bool transportIsValid;
  final String? transportWarning;
  final bool synchronizationDue;
  final Duration synchronizationDelay;

  const SmartSyncDecisionContext({
    required this.sample,
    required this.networkStatus,
    required this.batteryState,
    required this.movementState,
    required this.healthStatus,
    required this.offlineQueueSize,
    required this.retryCount,
    required this.isEmergency,
    this.transportIsValid = true,
    this.transportWarning,
    this.synchronizationDue = true,
    this.synchronizationDelay = Duration.zero,
  });
}
