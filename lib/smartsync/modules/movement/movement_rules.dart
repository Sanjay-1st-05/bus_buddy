class MovementRules {
  final double movementThresholdMeters;
  final double stationarySpeedMetersPerSecond;
  final double movingSpeedMetersPerSecond;
  final double accelerationDeltaMetersPerSecond;
  final double turningHeadingDeltaDegrees;
  final double maxGpsAccuracyMeters;
  final double impossibleJumpSpeedMetersPerSecond;
  final Duration idleDuration;

  const MovementRules({
    required this.movementThresholdMeters,
    required this.stationarySpeedMetersPerSecond,
    required this.movingSpeedMetersPerSecond,
    required this.accelerationDeltaMetersPerSecond,
    required this.turningHeadingDeltaDegrees,
    required this.maxGpsAccuracyMeters,
    required this.impossibleJumpSpeedMetersPerSecond,
    required this.idleDuration,
  });

  const MovementRules.defaults()
    : movementThresholdMeters = 20,
      stationarySpeedMetersPerSecond = 0.8,
      movingSpeedMetersPerSecond = 1.5,
      accelerationDeltaMetersPerSecond = 2,
      turningHeadingDeltaDegrees = 30,
      maxGpsAccuracyMeters = 80,
      impossibleJumpSpeedMetersPerSecond = 70,
      idleDuration = const Duration(minutes: 3);
}
