import 'package:esec_bus/smartsync/models/smartsync_enums.dart';

class PowerOptimizationRules {
  final Map<BatteryMode, int> batteryThresholds;
  final Map<BatteryMode, double> syncIntervalMultipliers;
  final Map<BatteryMode, double> gpsIntervalMultipliers;
  final bool chargingUsesNormalMode;

  const PowerOptimizationRules({
    required this.batteryThresholds,
    required this.syncIntervalMultipliers,
    required this.gpsIntervalMultipliers,
    required this.chargingUsesNormalMode,
  });

  const PowerOptimizationRules.defaults()
    : batteryThresholds = const {
        BatteryMode.normal: 50,
        BatteryMode.balanced: 20,
        BatteryMode.powerSaving: 10,
        BatteryMode.emergencySaving: 0,
      },
      syncIntervalMultipliers = const {
        BatteryMode.normal: 1,
        BatteryMode.balanced: 1.5,
        BatteryMode.powerSaving: 2.5,
        BatteryMode.emergencySaving: 4,
      },
      gpsIntervalMultipliers = const {
        BatteryMode.normal: 1,
        BatteryMode.balanced: 1.5,
        BatteryMode.powerSaving: 3,
        BatteryMode.emergencySaving: 5,
      },
      chargingUsesNormalMode = true;

  double syncMultiplierFor(BatteryMode mode) {
    return syncIntervalMultipliers[mode] ?? 1;
  }

  double gpsMultiplierFor(BatteryMode mode) {
    return gpsIntervalMultipliers[mode] ?? 1;
  }
}
