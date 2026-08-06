class TransportPolicy {
  final double movementThresholdMeters;
  final double geofenceRadiusMeters;
  final double maxReliableSpeedMetersPerSecond;
  final Duration staleLocationAfter;
  final bool emergencyPriorityEnabled;
  final bool routeAwarenessRequired;

  const TransportPolicy({
    required this.movementThresholdMeters,
    required this.geofenceRadiusMeters,
    required this.maxReliableSpeedMetersPerSecond,
    required this.staleLocationAfter,
    required this.emergencyPriorityEnabled,
    required this.routeAwarenessRequired,
  });
}
