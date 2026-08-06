class PacketOptimizationRules {
  final int coordinatePrecision;
  final int speedPrecision;
  final int headingPrecision;
  final int accuracyPrecision;
  final bool includeMetadata;
  final bool compactKeys;

  const PacketOptimizationRules({
    required this.coordinatePrecision,
    required this.speedPrecision,
    required this.headingPrecision,
    required this.accuracyPrecision,
    required this.includeMetadata,
    required this.compactKeys,
  });

  const PacketOptimizationRules.defaults()
    : coordinatePrecision = 6,
      speedPrecision = 2,
      headingPrecision = 1,
      accuracyPrecision = 1,
      includeMetadata = false,
      compactKeys = true;

  const PacketOptimizationRules.compatible()
    : coordinatePrecision = 6,
      speedPrecision = 2,
      headingPrecision = 1,
      accuracyPrecision = 1,
      includeMetadata = true,
      compactKeys = false;
}
