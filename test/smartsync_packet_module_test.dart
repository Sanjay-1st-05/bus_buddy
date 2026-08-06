import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('PacketOptimizationModule', () {
    final packet = SyncPacket(
      packetId: 'packet-1',
      deviceId: 'driver-phone-1',
      transportId: 'BUS_01',
      sample: LocationSample(
        latitude: 11.016812349,
        longitude: 76.955856789,
        speedMetersPerSecond: 8.456,
        headingDegrees: 90.27,
        accuracyMeters: 6.44,
        capturedAt: DateTime.utc(2026, 7, 11, 10),
      ),
      metadata: const {'routeName': 'College Main Route', 'debugOnly': true},
    );

    test(
      'creates compact payload with field aliases and rounded precision',
      () {
        const optimizer = PacketOptimizationModule();

        final payload = optimizer.optimize(packet);

        expect(payload.isCompact, isTrue);
        expect(payload.metadataIncluded, isFalse);
        expect(payload.data['id'], 'packet-1');
        expect(payload.data['d'], 'driver-phone-1');
        expect(payload.data['t'], 'BUS_01');
        expect(payload.data['la'], 11.016812);
        expect(payload.data['lo'], 76.955857);
        expect(payload.data['s'], 8.46);
        expect(payload.data['h'], 90.3);
        expect(payload.data['a'], 6.4);
        expect(payload.data.containsKey('latitude'), isFalse);
        expect(payload.data.containsKey('metadata'), isFalse);
        expect(payload.estimatedBytes, greaterThan(0));
      },
    );

    test('can include metadata in compact payload when explicitly enabled', () {
      const optimizer = PacketOptimizationModule(
        rules: PacketOptimizationRules(
          coordinatePrecision: 6,
          speedPrecision: 2,
          headingPrecision: 1,
          accuracyPrecision: 1,
          includeMetadata: true,
          compactKeys: true,
        ),
      );

      final payload = optimizer.optimize(packet);

      expect(payload.metadataIncluded, isTrue);
      expect(payload.data['m'], packet.metadata);
    });

    test('supports backward-compatible descriptive payload keys', () {
      const optimizer = PacketOptimizationModule(
        rules: PacketOptimizationRules.compatible(),
      );

      final payload = optimizer.optimize(packet);

      expect(payload.isCompact, isFalse);
      expect(payload.data['packetId'], 'packet-1');
      expect(payload.data['deviceId'], 'driver-phone-1');
      expect(payload.data['transportId'], 'BUS_01');
      expect(payload.data['latitude'], 11.016812);
      expect(payload.data['longitude'], 76.955857);
      expect(payload.data['speed'], 8.46);
      expect(payload.data['heading'], 90.3);
      expect(payload.data['accuracy'], 6.4);
      expect(payload.data['metadata'], packet.metadata);
      expect(payload.data.containsKey('la'), isFalse);
    });

    test('compact payload is smaller than compatible payload', () {
      const compactOptimizer = PacketOptimizationModule();
      const compatibleOptimizer = PacketOptimizationModule(
        rules: PacketOptimizationRules.compatible(),
      );

      final compact = compactOptimizer.optimize(packet);
      final compatible = compatibleOptimizer.optimize(packet);

      expect(compact.estimatedBytes, lessThan(compatible.estimatedBytes));
    });

    test('respects custom precision rules', () {
      const optimizer = PacketOptimizationModule(
        rules: PacketOptimizationRules(
          coordinatePrecision: 4,
          speedPrecision: 1,
          headingPrecision: 0,
          accuracyPrecision: 0,
          includeMetadata: false,
          compactKeys: true,
        ),
      );

      final payload = optimizer.optimize(packet);

      expect(payload.data['la'], 11.0168);
      expect(payload.data['lo'], 76.9559);
      expect(payload.data['s'], 8.5);
      expect(payload.data['h'], 90);
      expect(payload.data['a'], 6);
    });
  });
}
