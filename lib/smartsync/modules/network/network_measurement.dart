class NetworkMeasurement {
  final bool isConnected;
  final Duration latency;
  final double packetLossPercent;
  final double signalStability;
  final DateTime measuredAt;
  final String? source;

  const NetworkMeasurement({
    required this.isConnected,
    required this.latency,
    required this.packetLossPercent,
    required this.signalStability,
    required this.measuredAt,
    this.source,
  });
}
