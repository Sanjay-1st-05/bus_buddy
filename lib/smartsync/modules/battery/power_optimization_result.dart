import 'package:esec_bus/smartsync/models/battery_state.dart';

class PowerOptimizationResult {
  final BatteryState batteryState;
  final Duration adjustedSyncInterval;
  final Duration adjustedGpsInterval;
  final bool shouldReduceGpsFrequency;
  final bool shouldReduceSyncFrequency;
  final String reason;

  const PowerOptimizationResult({
    required this.batteryState,
    required this.adjustedSyncInterval,
    required this.adjustedGpsInterval,
    required this.shouldReduceGpsFrequency,
    required this.shouldReduceSyncFrequency,
    required this.reason,
  });
}
