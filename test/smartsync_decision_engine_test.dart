import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('CentralDecisionEngine', () {
    late CentralDecisionEngine engine;

    setUp(() {
      engine = CentralDecisionEngine.defaults();
    });

    test('prioritizes emergency synchronization', () {
      final decision = engine.decide(_context(isEmergency: true));

      expect(decision.action, SyncAction.emergencySend);
      expect(decision.isEmergency, isTrue);
      expect(decision.shouldCompress, isFalse);
    });

    test('drops invalid GPS samples before attempting synchronization', () {
      final decision = engine.decide(
        _context(
          sample: LocationSample(
            latitude: 0,
            longitude: 0,
            capturedAt: DateTime.utc(2026),
          ),
        ),
      );

      expect(decision.action, SyncAction.drop);
      expect(decision.reason, 'invalid gps coordinates');
    });

    test('queues packets while the network is offline', () {
      final decision = engine.decide(
        _context(networkStatus: _network(NetworkQuality.offline)),
      );

      expect(decision.action, SyncAction.queueOffline);
      expect(decision.reason, 'network offline');
    });

    test('drops packets when offline queue capacity is reached', () {
      final decision = engine.decide(
        _context(
          offlineQueueSize: SmartSyncConfig.defaults().maxOfflineQueueSize,
        ),
      );

      expect(decision.action, SyncAction.drop);
      expect(decision.reason, 'offline queue capacity reached');
    });

    test('queues packets after retry budget is exhausted', () {
      final decision = engine.decide(
        _context(retryCount: SmartSyncConfig.defaults().maxRetryCount),
      );

      expect(decision.action, SyncAction.queueOffline);
      expect(decision.reason, 'maximum retry count reached');
    });

    test('waits when health is critical', () {
      final decision = engine.decide(
        _context(
          healthStatus: const HealthStatus(
            score: 20,
            severity: HealthSeverity.critical,
          ),
        ),
      );

      expect(decision.action, SyncAction.wait);
      expect(decision.waitDuration, const Duration(seconds: 30));
    });

    test('waits during battery emergency saving mode', () {
      final decision = engine.decide(
        _context(
          batteryState: const BatteryState(
            levelPercent: 9,
            isCharging: false,
            mode: BatteryMode.emergencySaving,
          ),
        ),
      );

      expect(decision.action, SyncAction.wait);
      expect(decision.reason, 'battery emergency saving mode');
    });

    test('waits for stationary vehicles below movement threshold', () {
      final decision = engine.decide(
        _context(
          movementState: const MovementState(
            type: MovementType.stopped,
            distanceSinceLastSyncMeters: 5,
          ),
        ),
      );

      expect(decision.action, SyncAction.wait);
      expect(decision.reason, 'movement threshold not reached');
    });

    test('sends when all core signals are accepted', () {
      final decision = engine.decide(_context());

      expect(decision.action, SyncAction.sendNow);
      expect(decision.reason, contains('accepted'));
    });

    test('compresses packets on weaker networks', () {
      final decision = engine.decide(
        _context(networkStatus: _network(NetworkQuality.weak)),
      );

      expect(decision.action, SyncAction.sendNow);
      expect(decision.shouldCompress, isTrue);
    });

    test(
      'emergency priority bypasses offline, health, battery, and queue gates',
      () {
        final decision = engine.decide(
          _context(
            isEmergency: true,
            networkStatus: _network(NetworkQuality.offline),
            offlineQueueSize: SmartSyncConfig.defaults().maxOfflineQueueSize,
            retryCount: SmartSyncConfig.defaults().maxRetryCount,
            batteryState: const BatteryState(
              levelPercent: 5,
              isCharging: false,
              mode: BatteryMode.emergencySaving,
            ),
            healthStatus: const HealthStatus(
              score: 10,
              severity: HealthSeverity.critical,
            ),
          ),
        );

        expect(decision.action, SyncAction.emergencySend);
        expect(decision.shouldCompress, isFalse);
      },
    );

    test('invalid GPS still drops when emergency priority is disabled', () {
      final disabledEmergencyEngine = CentralDecisionEngine(
        rules: DecisionEngineRules.defaults(
          config: SmartSyncConfig(
            syncIntervals: SmartSyncConfig.defaults().syncIntervals,
            movementThresholdMeters: 20,
            maxRetryCount: 3,
            maxOfflineQueueSize: 1000,
            geofenceRadiusMeters: 100,
            predictionWindow: const Duration(seconds: 30),
            batteryThresholds: SmartSyncConfig.defaults().batteryThresholds,
            emergencyPriorityEnabled: false,
            transportType: TransportType.collegeBus,
          ),
        ),
      );

      final decision = disabledEmergencyEngine.decide(
        _context(
          isEmergency: true,
          sample: LocationSample(
            latitude: 0,
            longitude: 0,
            capturedAt: DateTime.utc(2026),
          ),
        ),
      );

      expect(decision.action, SyncAction.drop);
      expect(decision.reason, 'invalid gps coordinates');
    });

    test('stationary vehicle sends after passing movement threshold', () {
      final decision = engine.decide(
        _context(
          movementState: const MovementState(
            type: MovementType.stopped,
            distanceSinceLastSyncMeters: 25,
          ),
        ),
      );

      expect(decision.action, SyncAction.sendNow);
    });

    test('transport validation is enforced by the Decision Engine', () {
      final decision = engine.decide(
        _context(transportIsValid: false, transportWarning: 'stale packet'),
      );

      expect(decision.action, SyncAction.drop);
      expect(decision.reason, 'stale packet');
    });

    test('adaptive synchronization wait is decided centrally', () {
      final decision = engine.decide(
        _context(
          synchronizationDue: false,
          synchronizationDelay: const Duration(seconds: 12),
        ),
      );

      expect(decision.action, SyncAction.wait);
      expect(decision.waitDuration, const Duration(seconds: 12));
    });
  });
}

SmartSyncDecisionContext _context({
  LocationSample? sample,
  NetworkStatus? networkStatus,
  BatteryState? batteryState,
  MovementState? movementState,
  HealthStatus? healthStatus,
  int offlineQueueSize = 0,
  int retryCount = 0,
  bool isEmergency = false,
  bool transportIsValid = true,
  String? transportWarning,
  bool synchronizationDue = true,
  Duration synchronizationDelay = Duration.zero,
}) {
  return SmartSyncDecisionContext(
    sample:
        sample ??
        LocationSample(
          latitude: 11.341,
          longitude: 77.7172,
          capturedAt: DateTime.utc(2026, 7, 12, 10),
        ),
    networkStatus: networkStatus ?? _network(NetworkQuality.good),
    batteryState:
        batteryState ??
        const BatteryState(
          levelPercent: 80,
          isCharging: false,
          mode: BatteryMode.normal,
        ),
    movementState:
        movementState ??
        const MovementState(
          type: MovementType.moving,
          distanceSinceLastSyncMeters: 30,
        ),
    healthStatus:
        healthStatus ??
        const HealthStatus(score: 100, severity: HealthSeverity.info),
    offlineQueueSize: offlineQueueSize,
    retryCount: retryCount,
    isEmergency: isEmergency,
    transportIsValid: transportIsValid,
    transportWarning: transportWarning,
    synchronizationDue: synchronizationDue,
    synchronizationDelay: synchronizationDelay,
  );
}

NetworkStatus _network(NetworkQuality quality) {
  return NetworkStatus(
    quality: quality,
    latency: const Duration(milliseconds: 250),
    packetLossPercent: quality == NetworkQuality.offline ? 100 : 1,
    signalStability: quality == NetworkQuality.offline ? 0 : 0.9,
    measuredAt: DateTime.utc(2026, 7, 12, 10),
  );
}
