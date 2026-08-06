import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('MotionIntelligenceModule', () {
    const module = MotionIntelligenceModule();

    LocationSample sample({
      required double latitude,
      required double longitude,
      required DateTime capturedAt,
      double? speed,
      double? heading,
      double? accuracy,
    }) {
      return LocationSample(
        latitude: latitude,
        longitude: longitude,
        capturedAt: capturedAt,
        speedMetersPerSecond: speed,
        headingDegrees: heading,
        accuracyMeters: accuracy,
      );
    }

    test('rejects invalid placeholder coordinates', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
        ),
        current: sample(
          latitude: 0,
          longitude: 0,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 5),
        ),
      );

      expect(analysis.shouldAcceptForSync, isFalse);
      expect(analysis.state.type, MovementType.stopped);
      expect(analysis.reason, 'invalid_coordinates');
    });

    test('rejects poor GPS accuracy as suspected drift', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          accuracy: 10,
        ),
        current: sample(
          latitude: 11.0170,
          longitude: 76.9560,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 5),
          accuracy: 120,
        ),
      );

      expect(analysis.shouldAcceptForSync, isFalse);
      expect(analysis.isGpsDriftSuspected, isTrue);
      expect(analysis.reason, 'poor_gps_accuracy');
    });

    test('does not accept stationary movement below threshold', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 0,
        ),
        current: sample(
          latitude: 11.01681,
          longitude: 76.95581,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 10),
          speed: 0,
        ),
      );

      expect(analysis.shouldAcceptForSync, isFalse);
      expect(analysis.state.type, MovementType.stopped);
      expect(analysis.reason, 'movement_below_threshold');
    });

    test('accepts meaningful movement over configured threshold', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 4,
        ),
        current: sample(
          latitude: 11.0171,
          longitude: 76.9561,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 10),
          speed: 4.5,
        ),
      );

      expect(analysis.shouldAcceptForSync, isTrue);
      expect(analysis.state.type, MovementType.moving);
      expect(analysis.distanceMeters, greaterThan(20));
      expect(analysis.reason, 'movement_threshold_passed');
      expect(analysis.state.lastAcceptedSample, isNotNull);
    });

    test('detects acceleration when speed increases sharply', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 1,
        ),
        current: sample(
          latitude: 11.0171,
          longitude: 76.9561,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 10),
          speed: 4,
        ),
      );

      expect(analysis.state.type, MovementType.accelerating);
      expect(analysis.speedDeltaMetersPerSecond, 3);
      expect(analysis.shouldAcceptForSync, isTrue);
    });

    test('detects turning from heading change', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 4,
          heading: 350,
        ),
        current: sample(
          latitude: 11.0171,
          longitude: 76.9561,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 10),
          speed: 4,
          heading: 20,
        ),
      );

      expect(analysis.state.type, MovementType.turning);
      expect(analysis.headingDeltaDegrees, 30);
      expect(analysis.shouldAcceptForSync, isTrue);
    });

    test('detects parked state after long stationary duration', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 0,
        ),
        current: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 4),
          speed: 0,
        ),
      );

      expect(analysis.state.type, MovementType.parked);
      expect(analysis.shouldAcceptForSync, isFalse);
      expect(analysis.reason, 'movement_below_threshold');
    });

    test('rejects impossible GPS jumps as suspected drift', () {
      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
        ),
        current: sample(
          latitude: 11.1168,
          longitude: 76.9558,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 3),
        ),
      );

      expect(analysis.shouldAcceptForSync, isFalse);
      expect(analysis.isGpsDriftSuspected, isTrue);
      expect(analysis.reason, 'impossible_jump');
    });

    test('uses last accepted sample for movement threshold distance', () {
      final lastAccepted = sample(
        latitude: 11.0168,
        longitude: 76.9558,
        capturedAt: DateTime.utc(2026, 7, 11, 9, 59),
      );

      final analysis = module.analyzeMovement(
        previous: sample(
          latitude: 11.0169,
          longitude: 76.9559,
          capturedAt: DateTime.utc(2026, 7, 11, 10),
          speed: 4,
        ),
        current: sample(
          latitude: 11.0171,
          longitude: 76.9561,
          capturedAt: DateTime.utc(2026, 7, 11, 10, 0, 10),
          speed: 4,
        ),
        lastAcceptedSample: lastAccepted,
      );

      expect(analysis.distanceMeters, greaterThan(20));
      expect(analysis.shouldAcceptForSync, isTrue);
    });
  });

  group('GeoDistance', () {
    test('normalizes heading deltas around 360 degrees', () {
      expect(GeoDistance.headingDelta(350, 20), 30);
      expect(GeoDistance.headingDelta(20, 350), 30);
    });
  });
}
