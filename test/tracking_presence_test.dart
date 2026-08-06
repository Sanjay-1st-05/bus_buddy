import 'package:flutter_test/flutter_test.dart';

import 'package:esec_bus/features/tracking/services/tracking_presence.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 8);

  test('inactive trip is stopped even when a heartbeat exists', () {
    final presence = TrackingPresence.evaluate(
      isActive: false,
      hasValidLocation: true,
      coordinateCapturedAt: now,
      serviceHeartbeatAt: now,
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.stopped);
  });

  test('active trip without a signal is delayed', () {
    final presence = TrackingPresence.evaluate(
      isActive: true,
      hasValidLocation: false,
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.delayed);
    expect(presence.isConnected, isFalse);
  });

  test('fresh heartbeat without a coordinate is starting GPS', () {
    final presence = TrackingPresence.evaluate(
      isActive: true,
      hasValidLocation: false,
      serviceHeartbeatAt: now.subtract(const Duration(seconds: 30)),
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.startingGps);
    expect(presence.isConnected, isTrue);
  });

  test('fresh heartbeat distinguishes a stationary bus', () {
    final presence = TrackingPresence.evaluate(
      isActive: true,
      hasValidLocation: true,
      coordinateCapturedAt: now.subtract(const Duration(minutes: 4)),
      serviceHeartbeatAt: now.subtract(const Duration(seconds: 20)),
      speedMetersPerSecond: 0,
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.stationary);
    expect(presence.isConnected, isTrue);
  });

  test('fresh coordinate supports clients before the first heartbeat', () {
    final presence = TrackingPresence.evaluate(
      isActive: true,
      hasValidLocation: true,
      coordinateCapturedAt: now.subtract(const Duration(seconds: 20)),
      speedMetersPerSecond: 5,
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.live);
  });

  test('stale heartbeat and coordinate are disconnected', () {
    final presence = TrackingPresence.evaluate(
      isActive: true,
      hasValidLocation: true,
      coordinateCapturedAt: now.subtract(const Duration(minutes: 5)),
      serviceHeartbeatAt: now.subtract(const Duration(minutes: 2)),
      speedMetersPerSecond: 0,
      now: now,
    );

    expect(presence.status, TrackingPresenceStatus.delayed);
    expect(presence.isConnected, isFalse);
  });
}
