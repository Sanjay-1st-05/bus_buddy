class PredictionRules {
  final Duration predictionWindow;
  final double minimumSpeedMetersPerSecond;
  final double confidenceDecayPerSecond;
  final double roadDirectionConfidenceBonus;
  final double historicalMovementConfidenceBonus;
  final double minimumConfidence;

  const PredictionRules({
    required this.predictionWindow,
    required this.minimumSpeedMetersPerSecond,
    required this.confidenceDecayPerSecond,
    required this.roadDirectionConfidenceBonus,
    required this.historicalMovementConfidenceBonus,
    required this.minimumConfidence,
  });

  const PredictionRules.defaults()
    : predictionWindow = const Duration(seconds: 30),
      minimumSpeedMetersPerSecond = 0.8,
      confidenceDecayPerSecond = 0.02,
      roadDirectionConfidenceBonus = 0.08,
      historicalMovementConfidenceBonus = 0.06,
      minimumConfidence = 0.1;
}
