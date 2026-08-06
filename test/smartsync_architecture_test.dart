import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('SmartSync architecture foundation', () {
    test('default configuration exposes expected adaptive intervals', () {
      final config = SmartSyncConfig.defaults();

      expect(
        config.intervalFor(NetworkQuality.excellent),
        const Duration(seconds: 3),
      );
      expect(
        config.intervalFor(NetworkQuality.good),
        const Duration(seconds: 5),
      );
      expect(
        config.intervalFor(NetworkQuality.average),
        const Duration(seconds: 10),
      );
      expect(
        config.intervalFor(NetworkQuality.weak),
        const Duration(seconds: 25),
      );
      expect(config.intervalFor(NetworkQuality.offline), Duration.zero);
    });

    test(
      'location sample rejects placeholder and out-of-range coordinates',
      () {
        final placeholder = LocationSample(
          latitude: 0,
          longitude: 0,
          capturedAt: DateTime.utc(2026),
        );
        final invalid = LocationSample(
          latitude: 120,
          longitude: 77,
          capturedAt: DateTime.utc(2026),
        );
        final valid = LocationSample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026),
        );

        expect(placeholder.hasValidCoordinates, isFalse);
        expect(invalid.hasValidCoordinates, isFalse);
        expect(valid.hasValidCoordinates, isTrue);
      },
    );

    test('sync packet supports compact field aliases', () {
      final packet = SyncPacket(
        packetId: 'p1',
        deviceId: 'device-1',
        transportId: 'BUS_01',
        sample: LocationSample(
          latitude: 11.01681234,
          longitude: 76.95585678,
          speedMetersPerSecond: 8,
          headingDegrees: 90,
          capturedAt: DateTime.utc(2026, 7, 11),
        ),
      );

      final json = packet.toCompactJson();

      expect(json['la'], 11.016812);
      expect(json['lo'], 76.955857);
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
    });

    test('offline decisions are explicit and reusable', () {
      const decision = SyncDecision.queueOffline();

      expect(decision.action, SyncAction.queueOffline);
      expect(decision.reason, 'offline');
      expect(decision.shouldCompress, isTrue);
    });
  });
}
