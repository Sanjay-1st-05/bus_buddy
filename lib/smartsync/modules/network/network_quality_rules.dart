class NetworkQualityRules {
  final Duration excellentMaxLatency;
  final Duration goodMaxLatency;
  final Duration averageMaxLatency;
  final double excellentMaxPacketLossPercent;
  final double goodMaxPacketLossPercent;
  final double averageMaxPacketLossPercent;
  final double excellentMinSignalStability;
  final double goodMinSignalStability;
  final double averageMinSignalStability;

  const NetworkQualityRules({
    required this.excellentMaxLatency,
    required this.goodMaxLatency,
    required this.averageMaxLatency,
    required this.excellentMaxPacketLossPercent,
    required this.goodMaxPacketLossPercent,
    required this.averageMaxPacketLossPercent,
    required this.excellentMinSignalStability,
    required this.goodMinSignalStability,
    required this.averageMinSignalStability,
  });

  const NetworkQualityRules.defaults()
    : excellentMaxLatency = const Duration(milliseconds: 150),
      goodMaxLatency = const Duration(milliseconds: 350),
      averageMaxLatency = const Duration(milliseconds: 1000),
      excellentMaxPacketLossPercent = 1,
      goodMaxPacketLossPercent = 3,
      averageMaxPacketLossPercent = 8,
      excellentMinSignalStability = 0.9,
      goodMinSignalStability = 0.75,
      averageMinSignalStability = 0.5;
}
