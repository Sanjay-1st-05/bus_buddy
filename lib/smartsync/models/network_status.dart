import 'smartsync_enums.dart';

class NetworkStatus {
  final NetworkQuality quality;
  final Duration latency;
  final double packetLossPercent;
  final double signalStability;
  final DateTime measuredAt;

  const NetworkStatus({
    required this.quality,
    required this.latency,
    required this.packetLossPercent,
    required this.signalStability,
    required this.measuredAt,
  });

  bool get isOffline => quality == NetworkQuality.offline;
}
