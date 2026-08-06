import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('EmergencyCommunicationModule', () {
    final triggeredAt = DateTime.utc(2026, 7, 12, 10);

    EmergencyEvent event(EmergencyTriggerType triggerType) {
      return EmergencyEvent(
        eventId: 'emergency-1',
        deviceId: 'driver-phone-1',
        transportId: 'BUS_01',
        triggerType: triggerType,
        triggeredAt: triggeredAt,
        location: LocationSample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: triggeredAt,
        ),
        metadata: const {'source': 'test'},
      );
    }

    test('creates immediate emergency send decision for SOS trigger', () {
      const module = EmergencyCommunicationModule();

      final result = module.handle(event(EmergencyTriggerType.sos));

      expect(result.decision.action, SyncAction.emergencySend);
      expect(result.decision.isEmergency, isTrue);
      expect(result.decision.shouldCompress, isFalse);
      expect(result.shouldBypassNormalInterval, isTrue);
      expect(result.shouldBypassCompression, isTrue);
      expect(result.maxRetryCount, 5);
      expect(result.reason, 'emergency_sync_required');
    });

    test('supports panic button, crash detection, and panic mode triggers', () {
      const module = EmergencyCommunicationModule();

      for (final trigger in EmergencyTriggerType.values) {
        final result = module.handle(event(trigger));

        expect(result.event.triggerType, trigger);
        expect(result.decision.action, SyncAction.emergencySend);
      }
    });

    test('uses aggressive retry delays', () {
      const rules = EmergencyRules.defaults();

      expect(rules.retryDelayForAttempt(1), const Duration(milliseconds: 500));
      expect(rules.retryDelayForAttempt(2), const Duration(seconds: 1));
      expect(rules.retryDelayForAttempt(5), const Duration(seconds: 5));
      expect(rules.retryDelayForAttempt(99), const Duration(seconds: 5));
    });

    test('can disable emergency priority from configuration', () {
      final config = SmartSyncConfig(
        syncIntervals: SmartSyncConfig.defaults().syncIntervals,
        movementThresholdMeters: 20,
        maxRetryCount: 3,
        maxOfflineQueueSize: 1000,
        geofenceRadiusMeters: 100,
        predictionWindow: const Duration(seconds: 30),
        batteryThresholds: SmartSyncConfig.defaults().batteryThresholds,
        emergencyPriorityEnabled: false,
        transportType: TransportType.collegeBus,
      );
      final module = EmergencyCommunicationModule.fromConfig(config);

      final result = module.handle(event(EmergencyTriggerType.crashDetection));

      expect(result.decision.action, SyncAction.wait);
      expect(result.decision.isEmergency, isFalse);
      expect(result.maxRetryCount, 0);
      expect(result.shouldBypassNormalInterval, isFalse);
      expect(result.reason, 'emergency_priority_disabled');
    });

    test('preserves emergency event metadata and location', () {
      const module = EmergencyCommunicationModule();

      final result = module.handle(event(EmergencyTriggerType.panicButton));

      expect(result.event.metadata['source'], 'test');
      expect(result.event.location?.hasValidCoordinates, isTrue);
      expect(result.event.transportId, 'BUS_01');
    });
  });
}
