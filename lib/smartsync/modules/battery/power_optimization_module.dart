import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/battery_state.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/battery/battery_reading.dart';
import 'package:esec_bus/smartsync/modules/battery/location_power_profile.dart';
import 'package:esec_bus/smartsync/modules/battery/power_optimization_result.dart';
import 'package:esec_bus/smartsync/modules/battery/power_optimization_rules.dart';

class PowerOptimizationModule implements SmartSyncPowerOptimizer {
  final PowerOptimizationRules rules;

  const PowerOptimizationModule({
    this.rules = const PowerOptimizationRules.defaults(),
  });

  factory PowerOptimizationModule.fromConfig(SmartSyncConfig config) {
    return PowerOptimizationModule(
      rules: PowerOptimizationRules(
        batteryThresholds: config.batteryThresholds,
        syncIntervalMultipliers:
            const PowerOptimizationRules.defaults().syncIntervalMultipliers,
        gpsIntervalMultipliers:
            const PowerOptimizationRules.defaults().gpsIntervalMultipliers,
        chargingUsesNormalMode:
            const PowerOptimizationRules.defaults().chargingUsesNormalMode,
      ),
    );
  }

  @override
  BatteryState classify(BatteryReading reading) {
    final level = reading.levelPercent.clamp(0, 100);
    final mode = _modeFor(level, reading.isCharging, reading.isPowerSaveMode);

    return BatteryState(
      levelPercent: level,
      isCharging: reading.isCharging,
      isPowerSaveMode: reading.isPowerSaveMode,
      mode: mode,
    );
  }

  @override
  LocationPowerProfile locationProfile({
    required BatteryReading reading,
    Duration baseGpsInterval = const Duration(seconds: 8),
    int baseDistanceFilterMeters = 20,
  }) {
    final optimized = optimize(
      reading: reading,
      baseSyncInterval: baseGpsInterval,
      baseGpsInterval: baseGpsInterval,
    );
    final state = optimized.batteryState;
    final multiplier = rules.gpsMultiplierFor(state.mode);

    return LocationPowerProfile(
      batteryState: state,
      gpsInterval: optimized.adjustedGpsInterval,
      distanceFilterMeters: (baseDistanceFilterMeters * multiplier).round(),
      accuracy: switch (state.mode) {
        BatteryMode.normal => LocationPowerAccuracy.high,
        BatteryMode.balanced => LocationPowerAccuracy.balanced,
        BatteryMode.powerSaving => LocationPowerAccuracy.balanced,
        BatteryMode.emergencySaving => LocationPowerAccuracy.lowPower,
      },
      reason: optimized.reason,
    );
  }

  @override
  PowerOptimizationResult optimize({
    required BatteryReading reading,
    required Duration baseSyncInterval,
    required Duration baseGpsInterval,
  }) {
    final batteryState = classify(reading);
    final adjustedSyncInterval = _scale(
      baseSyncInterval,
      rules.syncMultiplierFor(batteryState.mode),
    );
    final adjustedGpsInterval = _scale(
      baseGpsInterval,
      rules.gpsMultiplierFor(batteryState.mode),
    );

    return PowerOptimizationResult(
      batteryState: batteryState,
      adjustedSyncInterval: adjustedSyncInterval,
      adjustedGpsInterval: adjustedGpsInterval,
      shouldReduceGpsFrequency: adjustedGpsInterval > baseGpsInterval,
      shouldReduceSyncFrequency: adjustedSyncInterval > baseSyncInterval,
      reason: _reasonFor(batteryState.mode),
    );
  }

  BatteryMode _modeFor(
    int levelPercent,
    bool isCharging,
    bool isPowerSaveMode,
  ) {
    if (isCharging && rules.chargingUsesNormalMode) {
      return BatteryMode.normal;
    }
    final powerSavingThreshold =
        rules.batteryThresholds[BatteryMode.powerSaving] ?? 10;
    if (levelPercent < powerSavingThreshold) {
      return BatteryMode.emergencySaving;
    }
    if (isPowerSaveMode) {
      return BatteryMode.powerSaving;
    }

    final normalThreshold = rules.batteryThresholds[BatteryMode.normal] ?? 50;
    final balancedThreshold =
        rules.batteryThresholds[BatteryMode.balanced] ?? 20;
    if (levelPercent >= normalThreshold) return BatteryMode.normal;
    if (levelPercent >= balancedThreshold) return BatteryMode.balanced;
    if (levelPercent >= powerSavingThreshold) {
      return BatteryMode.powerSaving;
    }
    return BatteryMode.emergencySaving;
  }

  Duration _scale(Duration base, double multiplier) {
    if (base == Duration.zero) return Duration.zero;
    return Duration(milliseconds: (base.inMilliseconds * multiplier).round());
  }

  String _reasonFor(BatteryMode mode) {
    return switch (mode) {
      BatteryMode.normal => 'battery_normal',
      BatteryMode.balanced => 'battery_balanced',
      BatteryMode.powerSaving => 'battery_power_saving',
      BatteryMode.emergencySaving => 'battery_emergency_saving',
    };
  }
}
