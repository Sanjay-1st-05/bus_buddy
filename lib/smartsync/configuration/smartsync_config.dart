import 'package:esec_bus/smartsync/models/smartsync_enums.dart';

class SmartSyncConfig {
  final Map<NetworkQuality, Duration> syncIntervals;
  final double movementThresholdMeters;
  final int maxRetryCount;
  final int maxOfflineQueueSize;
  final double geofenceRadiusMeters;
  final Duration predictionWindow;
  final Map<BatteryMode, int> batteryThresholds;
  final bool emergencyPriorityEnabled;
  final TransportType transportType;

  const SmartSyncConfig({
    required this.syncIntervals,
    required this.movementThresholdMeters,
    required this.maxRetryCount,
    required this.maxOfflineQueueSize,
    required this.geofenceRadiusMeters,
    required this.predictionWindow,
    required this.batteryThresholds,
    required this.emergencyPriorityEnabled,
    required this.transportType,
  });

  factory SmartSyncConfig.defaults({
    TransportType transportType = TransportType.collegeBus,
  }) {
    return SmartSyncConfig(
      syncIntervals: const {
        NetworkQuality.excellent: Duration(seconds: 3),
        NetworkQuality.good: Duration(seconds: 5),
        NetworkQuality.average: Duration(seconds: 10),
        NetworkQuality.weak: Duration(seconds: 25),
        NetworkQuality.offline: Duration.zero,
      },
      movementThresholdMeters: 20,
      maxRetryCount: 3,
      maxOfflineQueueSize: 1000,
      geofenceRadiusMeters: 100,
      predictionWindow: const Duration(seconds: 30),
      batteryThresholds: const {
        BatteryMode.normal: 50,
        BatteryMode.balanced: 20,
        BatteryMode.powerSaving: 10,
        BatteryMode.emergencySaving: 0,
      },
      emergencyPriorityEnabled: true,
      transportType: transportType,
    );
  }

  Duration intervalFor(NetworkQuality quality) {
    return syncIntervals[quality] ?? Duration.zero;
  }
}
