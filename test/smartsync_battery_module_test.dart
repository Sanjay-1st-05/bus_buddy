import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('PowerOptimizationModule', () {
    const module = PowerOptimizationModule();
    final measuredAt = DateTime.utc(2026, 7, 11, 10);

    BatteryReading reading(int level, {bool isCharging = false}) {
      return BatteryReading(
        levelPercent: level,
        isCharging: isCharging,
        measuredAt: measuredAt,
      );
    }

    test('classifies battery levels into power modes', () {
      expect(module.classify(reading(100)).mode, BatteryMode.normal);
      expect(module.classify(reading(50)).mode, BatteryMode.normal);
      expect(module.classify(reading(49)).mode, BatteryMode.balanced);
      expect(module.classify(reading(20)).mode, BatteryMode.balanced);
      expect(module.classify(reading(19)).mode, BatteryMode.powerSaving);
      expect(module.classify(reading(10)).mode, BatteryMode.powerSaving);
      expect(module.classify(reading(9)).mode, BatteryMode.emergencySaving);
    });

    test('charging battery uses normal mode by default', () {
      final state = module.classify(reading(8, isCharging: true));

      expect(state.mode, BatteryMode.normal);
      expect(state.isCharging, isTrue);
    });

    test('Android power saver activates the power saving policy', () {
      final state = module.classify(
        BatteryReading(
          levelPercent: 85,
          isCharging: false,
          isPowerSaveMode: true,
          measuredAt: measuredAt,
        ),
      );

      expect(state.mode, BatteryMode.powerSaving);
      expect(state.isPowerSaveMode, isTrue);
    });

    test('clamps invalid battery level inputs safely', () {
      expect(module.classify(reading(150)).levelPercent, 100);
      expect(module.classify(reading(-10)).levelPercent, 0);
    });

    test('keeps normal mode intervals unchanged', () {
      final result = module.optimize(
        reading: reading(80),
        baseSyncInterval: const Duration(seconds: 5),
        baseGpsInterval: const Duration(seconds: 3),
      );

      expect(result.batteryState.mode, BatteryMode.normal);
      expect(result.adjustedSyncInterval, const Duration(seconds: 5));
      expect(result.adjustedGpsInterval, const Duration(seconds: 3));
      expect(result.shouldReduceSyncFrequency, isFalse);
      expect(result.shouldReduceGpsFrequency, isFalse);
    });

    test('balanced mode reduces sync and GPS frequency moderately', () {
      final result = module.optimize(
        reading: reading(30),
        baseSyncInterval: const Duration(seconds: 10),
        baseGpsInterval: const Duration(seconds: 4),
      );

      expect(result.batteryState.mode, BatteryMode.balanced);
      expect(result.adjustedSyncInterval, const Duration(seconds: 15));
      expect(result.adjustedGpsInterval, const Duration(seconds: 6));
      expect(result.shouldReduceSyncFrequency, isTrue);
      expect(result.shouldReduceGpsFrequency, isTrue);
      expect(result.reason, 'battery_balanced');
    });

    test('power saving mode strongly reduces GPS frequency', () {
      final result = module.optimize(
        reading: reading(15),
        baseSyncInterval: const Duration(seconds: 10),
        baseGpsInterval: const Duration(seconds: 4),
      );

      expect(result.batteryState.mode, BatteryMode.powerSaving);
      expect(result.adjustedSyncInterval, const Duration(seconds: 25));
      expect(result.adjustedGpsInterval, const Duration(seconds: 12));
      expect(result.reason, 'battery_power_saving');
    });

    test('emergency saving mode applies the strongest reduction', () {
      final result = module.optimize(
        reading: reading(5),
        baseSyncInterval: const Duration(seconds: 10),
        baseGpsInterval: const Duration(seconds: 4),
      );

      expect(result.batteryState.mode, BatteryMode.emergencySaving);
      expect(result.adjustedSyncInterval, const Duration(seconds: 40));
      expect(result.adjustedGpsInterval, const Duration(seconds: 20));
      expect(result.reason, 'battery_emergency_saving');
    });

    test('produces native GPS profiles for every battery mode', () {
      final normal = module.locationProfile(reading: reading(80));
      final balanced = module.locationProfile(reading: reading(30));
      final saving = module.locationProfile(reading: reading(15));
      final emergency = module.locationProfile(reading: reading(5));

      expect(normal.gpsInterval, const Duration(seconds: 8));
      expect(normal.distanceFilterMeters, 20);
      expect(normal.accuracy, LocationPowerAccuracy.high);

      expect(balanced.gpsInterval, const Duration(seconds: 12));
      expect(balanced.distanceFilterMeters, 30);
      expect(balanced.accuracy, LocationPowerAccuracy.balanced);

      expect(saving.gpsInterval, const Duration(seconds: 24));
      expect(saving.distanceFilterMeters, 60);
      expect(saving.accuracy, LocationPowerAccuracy.balanced);

      expect(emergency.gpsInterval, const Duration(seconds: 40));
      expect(emergency.distanceFilterMeters, 100);
      expect(emergency.accuracy, LocationPowerAccuracy.lowPower);
    });

    test('fromConfig uses configured thresholds', () {
      final config = SmartSyncConfig(
        syncIntervals: SmartSyncConfig.defaults().syncIntervals,
        movementThresholdMeters: 20,
        maxRetryCount: 3,
        maxOfflineQueueSize: 1000,
        geofenceRadiusMeters: 100,
        predictionWindow: const Duration(seconds: 30),
        batteryThresholds: const {
          BatteryMode.normal: 60,
          BatteryMode.balanced: 30,
          BatteryMode.powerSaving: 15,
          BatteryMode.emergencySaving: 0,
        },
        emergencyPriorityEnabled: true,
        transportType: TransportType.collegeBus,
      );
      final configured = PowerOptimizationModule.fromConfig(config);

      expect(configured.classify(reading(55)).mode, BatteryMode.balanced);
      expect(configured.classify(reading(25)).mode, BatteryMode.powerSaving);
      expect(
        configured.classify(reading(10)).mode,
        BatteryMode.emergencySaving,
      );
    });
  });
}
