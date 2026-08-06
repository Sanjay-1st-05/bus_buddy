import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('PredictiveTrackingModule', () {
    const module = PredictiveTrackingModule();
    final capturedAt = DateTime.utc(2026, 7, 11, 10);

    LocationSample sample({
      required double latitude,
      required double longitude,
      required DateTime capturedAt,
      double? speed,
      double? heading,
    }) {
      return LocationSample(
        latitude: latitude,
        longitude: longitude,
        capturedAt: capturedAt,
        speedMetersPerSecond: speed,
        headingDegrees: heading,
      );
    }

    test('stops prediction immediately when live GPS is available', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 8,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 5)),
          hasLiveGps: true,
        ),
      );

      expect(result.isActive, isFalse);
      expect(result.predictedPosition, isNull);
      expect(result.reason, 'live_gps_available');
    });

    test('predicts position from previous GPS speed and heading', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 10,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 10)),
        ),
      );

      expect(result.isActive, isTrue);
      expect(result.predictedPosition, isNotNull);
      expect(result.predictedPosition!.longitude, greaterThan(76.9558));
      expect(result.predictedPosition!.latitude, closeTo(11.0168, 0.001));
      expect(result.confidenceScore, closeTo(0.8, 0.001));
      expect(result.reason, 'prediction_active');
    });

    test('uses road direction when available', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 10,
            heading: 90,
          ),
          roadHeadingDegrees: 0,
          predictionTime: capturedAt.add(const Duration(seconds: 5)),
        ),
      );

      expect(result.isActive, isTrue);
      expect(result.predictedPosition!.latitude, greaterThan(11.0168));
      expect(result.predictedPosition!.longitude, closeTo(76.9558, 0.001));
      expect(result.confidenceScore, greaterThan(0.9));
    });

    test('calculates ETA when distance to destination is provided', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 10,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 5)),
          distanceToDestinationMeters: 1200,
        ),
      );

      expect(result.estimatedEta, const Duration(seconds: 120));
    });

    test('does not predict beyond configured prediction window', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 10,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 31)),
        ),
      );

      expect(result.isActive, isFalse);
      expect(result.reason, 'prediction_window_expired');
    });

    test('does not predict without usable speed', () {
      final result = module.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 5)),
        ),
      );

      expect(result.isActive, isFalse);
      expect(result.reason, 'speed_too_low');
    });

    test(
      'uses historical movement when direct speed and heading are absent',
      () {
        final previous = sample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: capturedAt.subtract(const Duration(seconds: 10)),
        );
        final current = sample(
          latitude: 11.0172,
          longitude: 76.9558,
          capturedAt: capturedAt,
        );

        final result = module.predict(
          PredictionInput(
            previousGps: current,
            historicalMovement: [previous, current],
            predictionTime: capturedAt.add(const Duration(seconds: 5)),
          ),
        );

        expect(result.isActive, isTrue);
        expect(result.predictedPosition!.latitude, greaterThan(11.0172));
        expect(result.confidenceScore, greaterThan(0.8));
      },
    );

    test('fromConfig uses configured prediction window', () {
      final configured = PredictiveTrackingModule.fromConfig(
        SmartSyncConfig.defaults(),
      );

      final result = configured.predict(
        PredictionInput(
          previousGps: sample(
            latitude: 11.0168,
            longitude: 76.9558,
            capturedAt: capturedAt,
            speed: 10,
            heading: 90,
          ),
          predictionTime: capturedAt.add(const Duration(seconds: 30)),
        ),
      );

      expect(result.isActive, isTrue);
    });
  });
}
