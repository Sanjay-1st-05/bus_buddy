import 'package:esec_bus/features/tracking/services/live_tracking_metrics.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:test/test.dart';

void main() {
  LocationSample location(double latitude, double longitude, {double? speed}) {
    return LocationSample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: speed,
      capturedAt: DateTime.utc(2026, 7, 23),
    );
  }

  test('shows arrived when the bus is at the student location', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 0),
      studentLocation: location(11, 77),
      isTripRunning: true,
    );

    expect(metrics.distanceLabel, '0 m away');
    expect(metrics.etaState, LiveEtaState.arrived);
    expect(metrics.etaLabel, 'Arrived');
  });

  test('uses actual driver speed for ETA', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 10),
      studentLocation: location(11.054, 77),
      isTripRunning: true,
    );

    expect(metrics.distanceMeters, closeTo(6004.5, 5));
    expect(metrics.etaState, LiveEtaState.estimated);
    expect(metrics.etaMinutes, 11);
    expect(metrics.etaLabel, '11 min');
    expect(metrics.usesEstimatedSpeed, isFalse);
  });

  test('uses average moving speed while a running bus is stationary', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 0),
      studentLocation: location(11.01, 77),
      isTripRunning: true,
    );

    expect(metrics.etaState, LiveEtaState.estimated);
    expect(metrics.etaMinutes, 3);
    expect(metrics.etaLabel, '3 min');
    expect(metrics.usesEstimatedSpeed, isTrue);
    expect(
      metrics.effectiveSpeedMetersPerSecond,
      LiveTrackingMetrics.averageMovingSpeedMetersPerSecond,
    );
  });

  test('shows stopped rather than an ETA for an inactive trip', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 10),
      studentLocation: location(11.01, 77),
      isTripRunning: false,
    );

    expect(metrics.etaState, LiveEtaState.stopped);
    expect(metrics.etaLabel, 'Stopped');
  });

  test('formats distance in metres below one kilometre', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 5),
      studentLocation: location(11.008, 77),
      isTripRunning: true,
    );

    expect(metrics.distanceMeters, closeTo(889.6, 5));
    expect(metrics.distanceLabel, '890 m away');
  });

  test('formats kilometre distance with one decimal place', () {
    final metrics = LiveTrackingMetrics.calculate(
      busLocation: location(11, 77, speed: 5),
      studentLocation: location(11.3324, 77),
      isTripRunning: true,
    );

    expect(metrics.distanceMeters, closeTo(36965, 20));
    expect(metrics.distanceLabel, '37.0 km away');
  });
}
