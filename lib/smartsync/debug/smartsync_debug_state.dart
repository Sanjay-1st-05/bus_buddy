import 'package:esec_bus/smartsync/debug/smartsync_debug_event.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_value_source.dart';
import 'package:esec_bus/smartsync/models/battery_state.dart';
import 'package:esec_bus/smartsync/models/movement_state.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/models/sync_decision.dart';

class SmartSyncDebugState {
  final NetworkStatus networkStatus;
  final Duration synchronizationInterval;
  final SyncDecision engineDecision;
  final int retryCount;
  final int offlineQueueSize;
  final double? gpsAccuracyMeters;
  final MovementState movementState;
  final BatteryState batteryState;
  final List<String> activeModules;
  final String routeStatus;
  final String geofenceStatus;
  final int healthScore;
  final Map<String, dynamic> runtimeMetrics;
  final Map<String, dynamic> moduleRuntime;
  final List<Map<String, dynamic>> runtimeSamples;
  final List<SmartSyncDebugEvent> recentEvents;
  final Map<String, SmartSyncDebugValueSource> valueSources;
  final DateTime updatedAt;

  const SmartSyncDebugState({
    required this.networkStatus,
    required this.synchronizationInterval,
    required this.engineDecision,
    required this.retryCount,
    required this.offlineQueueSize,
    required this.gpsAccuracyMeters,
    required this.movementState,
    required this.batteryState,
    required this.activeModules,
    this.routeStatus = 'unavailable',
    this.geofenceStatus = 'none',
    this.healthScore = 0,
    this.runtimeMetrics = const {},
    this.moduleRuntime = const {},
    this.runtimeSamples = const [],
    required this.recentEvents,
    required this.valueSources,
    required this.updatedAt,
  });

  factory SmartSyncDebugState.initial({DateTime? now}) {
    final timestamp = now ?? DateTime.now();

    return SmartSyncDebugState(
      networkStatus: NetworkStatus(
        quality: NetworkQuality.offline,
        latency: Duration.zero,
        packetLossPercent: 100,
        signalStability: 0,
        measuredAt: timestamp,
      ),
      synchronizationInterval: Duration.zero,
      engineDecision: const SyncDecision.queueOffline(reason: 'initializing'),
      retryCount: 0,
      offlineQueueSize: 0,
      gpsAccuracyMeters: null,
      movementState: const MovementState(
        type: MovementType.stopped,
        distanceSinceLastSyncMeters: 0,
      ),
      batteryState: const BatteryState(
        levelPercent: 100,
        isCharging: false,
        mode: BatteryMode.normal,
      ),
      activeModules: const [],
      routeStatus: 'unavailable',
      geofenceStatus: 'none',
      healthScore: 0,
      runtimeMetrics: const {},
      moduleRuntime: const {},
      runtimeSamples: const [],
      recentEvents: const [],
      valueSources: const {},
      updatedAt: timestamp,
    );
  }

  SmartSyncDebugState copyWith({
    NetworkStatus? networkStatus,
    Duration? synchronizationInterval,
    SyncDecision? engineDecision,
    int? retryCount,
    int? offlineQueueSize,
    double? gpsAccuracyMeters,
    bool clearGpsAccuracy = false,
    MovementState? movementState,
    BatteryState? batteryState,
    List<String>? activeModules,
    String? routeStatus,
    String? geofenceStatus,
    int? healthScore,
    Map<String, dynamic>? runtimeMetrics,
    Map<String, dynamic>? moduleRuntime,
    List<Map<String, dynamic>>? runtimeSamples,
    List<SmartSyncDebugEvent>? recentEvents,
    Map<String, SmartSyncDebugValueSource>? valueSources,
    DateTime? updatedAt,
  }) {
    return SmartSyncDebugState(
      networkStatus: networkStatus ?? this.networkStatus,
      synchronizationInterval:
          synchronizationInterval ?? this.synchronizationInterval,
      engineDecision: engineDecision ?? this.engineDecision,
      retryCount: retryCount ?? this.retryCount,
      offlineQueueSize: offlineQueueSize ?? this.offlineQueueSize,
      gpsAccuracyMeters: clearGpsAccuracy
          ? null
          : gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      movementState: movementState ?? this.movementState,
      batteryState: batteryState ?? this.batteryState,
      activeModules: activeModules ?? this.activeModules,
      routeStatus: routeStatus ?? this.routeStatus,
      geofenceStatus: geofenceStatus ?? this.geofenceStatus,
      healthScore: healthScore ?? this.healthScore,
      runtimeMetrics: runtimeMetrics ?? this.runtimeMetrics,
      moduleRuntime: moduleRuntime ?? this.moduleRuntime,
      runtimeSamples: runtimeSamples ?? this.runtimeSamples,
      recentEvents: recentEvents ?? this.recentEvents,
      valueSources: valueSources ?? this.valueSources,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  SmartSyncDebugValueSource sourceFor(String key) {
    return valueSources[key] ?? SmartSyncDebugValueSource.fallback;
  }
}
