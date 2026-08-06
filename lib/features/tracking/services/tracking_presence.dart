enum TrackingPresenceStatus { stopped, startingGps, live, stationary, delayed }

class TrackingPresence {
  static const Duration connectionTimeout = Duration(seconds: 90);
  static const Duration stationaryThreshold = Duration(seconds: 60);

  final TrackingPresenceStatus status;
  final DateTime? lastSignalAt;

  const TrackingPresence({required this.status, this.lastSignalAt});

  bool get isConnected =>
      status == TrackingPresenceStatus.startingGps ||
      status == TrackingPresenceStatus.live ||
      status == TrackingPresenceStatus.stationary;

  static TrackingPresence evaluate({
    required bool isActive,
    required bool hasValidLocation,
    DateTime? coordinateCapturedAt,
    DateTime? serviceHeartbeatAt,
    double? speedMetersPerSecond,
    DateTime? now,
  }) {
    if (!isActive) {
      return TrackingPresence(
        status: TrackingPresenceStatus.stopped,
        lastSignalAt: serviceHeartbeatAt ?? coordinateCapturedAt,
      );
    }

    final evaluatedAt = now ?? DateTime.now();
    final lastSignalAt = serviceHeartbeatAt ?? coordinateCapturedAt;
    final hasFreshSignal =
        lastSignalAt != null &&
        evaluatedAt.difference(lastSignalAt) <= connectionTimeout;

    if (!hasFreshSignal) {
      return TrackingPresence(
        status: TrackingPresenceStatus.delayed,
        lastSignalAt: lastSignalAt,
      );
    }

    if (!hasValidLocation) {
      return TrackingPresence(
        status: TrackingPresenceStatus.startingGps,
        lastSignalAt: lastSignalAt,
      );
    }

    final coordinateAge = coordinateCapturedAt == null
        ? Duration.zero
        : evaluatedAt.difference(coordinateCapturedAt);
    final isStationary =
        (speedMetersPerSecond ?? 0).abs() < 0.8 &&
        coordinateAge >= stationaryThreshold;

    return TrackingPresence(
      status: isStationary
          ? TrackingPresenceStatus.stationary
          : TrackingPresenceStatus.live,
      lastSignalAt: lastSignalAt,
    );
  }
}
