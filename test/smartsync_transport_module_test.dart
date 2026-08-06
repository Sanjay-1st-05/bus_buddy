import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('MultiTransportModule', () {
    test('provides a profile for every supported transport type', () {
      final module = MultiTransportModule();

      for (final type in TransportType.values) {
        expect(module.supports(type), isTrue);
        expect(module.profileFor(type).type, type);
      }
    });

    test('loads different policies for different transport categories', () {
      final module = MultiTransportModule();

      final busPolicy = module.policyFor(TransportType.collegeBus);
      final ambulancePolicy = module.policyFor(TransportType.ambulance);
      final agriculturalPolicy = module.policyFor(
        TransportType.agriculturalVehicle,
      );

      expect(busPolicy.routeAwarenessRequired, isTrue);
      expect(ambulancePolicy.movementThresholdMeters, lessThan(10));
      expect(ambulancePolicy.emergencyPriorityEnabled, isTrue);
      expect(
        agriculturalPolicy.maxReliableSpeedMetersPerSecond,
        lessThan(busPolicy.maxReliableSpeedMetersPerSecond),
      );
    });

    test(
      'validates invalid coordinates, stale samples, and unrealistic speed',
      () {
        final module = MultiTransportModule();
        final now = DateTime.utc(2026, 7, 12, 10);
        final packet = SyncPacket(
          packetId: 'packet-1',
          deviceId: 'device-1',
          transportId: 'bus-1',
          sample: LocationSample(
            latitude: 0,
            longitude: 0,
            speedMetersPerSecond: 80,
            capturedAt: now.subtract(const Duration(minutes: 2)),
          ),
        );

        final result = module.validatePacket(
          packet: packet,
          type: TransportType.collegeBus,
          now: now,
        );

        expect(result.isValid, isFalse);
        expect(result.warnings, contains('Location coordinates are invalid.'));
        expect(
          result.warnings,
          contains('Location sample is stale for College Bus.'),
        );
        expect(
          result.warnings,
          contains('Reported speed is unrealistic for College Bus.'),
        );
      },
    );

    test('accepts valid packets for the selected transport profile', () {
      final module = MultiTransportModule();
      final now = DateTime.utc(2026, 7, 12, 10);
      final packet = SyncPacket(
        packetId: 'packet-2',
        deviceId: 'device-2',
        transportId: 'ambulance-1',
        sample: LocationSample(
          latitude: 11.341,
          longitude: 77.7172,
          speedMetersPerSecond: 20,
          capturedAt: now,
        ),
      );

      final result = module.validatePacket(
        packet: packet,
        type: TransportType.ambulance,
        now: now,
      );

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('supports dynamic profile overrides without changing the engine', () {
      final module = MultiTransportModule().mergeProfiles({
        TransportType.collegeBus: const TransportProfile(
          type: TransportType.collegeBus,
          name: 'Campus Express',
          policy: TransportPolicy(
            movementThresholdMeters: 12,
            geofenceRadiusMeters: 80,
            maxReliableSpeedMetersPerSecond: 28,
            staleLocationAfter: Duration(seconds: 20),
            emergencyPriorityEnabled: true,
            routeAwarenessRequired: true,
          ),
        ),
      });

      final profile = module.profileFor(TransportType.collegeBus);

      expect(profile.name, 'Campus Express');
      expect(profile.policy.movementThresholdMeters, 12);
      expect(profile.policy.staleLocationAfter, const Duration(seconds: 20));
    });

    test('throws clearly for unsupported profile registries', () {
      final module = MultiTransportModule(profiles: const {});

      expect(
        () => module.profileFor(TransportType.collegeBus),
        throwsA(isA<ArgumentError>()),
      );
      expect(module.supports(TransportType.collegeBus), isFalse);
    });

    test('treats stale boundary as valid until it exceeds policy', () {
      final module = MultiTransportModule();
      final now = DateTime.utc(2026, 7, 12, 10);
      final policy = module.policyFor(TransportType.taxi);
      final packet = SyncPacket(
        packetId: 'packet-boundary',
        deviceId: 'device-1',
        transportId: 'taxi-1',
        sample: LocationSample(
          latitude: 11.341,
          longitude: 77.7172,
          speedMetersPerSecond: 10,
          capturedAt: now.subtract(policy.staleLocationAfter),
        ),
      );

      final result = module.validatePacket(
        packet: packet,
        type: TransportType.taxi,
        now: now,
      );

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });
  });
}
