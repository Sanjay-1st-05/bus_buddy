import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/network/network_measurement.dart';
import 'package:esec_bus/smartsync/modules/network/network_quality_rules.dart';

class NetworkQualityClassifier {
  final NetworkQualityRules rules;

  const NetworkQualityClassifier({
    this.rules = const NetworkQualityRules.defaults(),
  });

  NetworkStatus classify(NetworkMeasurement measurement) {
    final packetLoss = _clampPercent(measurement.packetLossPercent);
    final stability = measurement.signalStability.clamp(0, 1).toDouble();
    final latency = measurement.latency.isNegative
        ? Duration.zero
        : measurement.latency;

    if (!measurement.isConnected) {
      return NetworkStatus(
        quality: NetworkQuality.offline,
        latency: latency,
        packetLossPercent: 100,
        signalStability: 0,
        measuredAt: measurement.measuredAt,
      );
    }

    return NetworkStatus(
      quality: _qualityFor(
        latency: latency,
        packetLossPercent: packetLoss,
        signalStability: stability,
      ),
      latency: latency,
      packetLossPercent: packetLoss,
      signalStability: stability,
      measuredAt: measurement.measuredAt,
    );
  }

  NetworkQuality _qualityFor({
    required Duration latency,
    required double packetLossPercent,
    required double signalStability,
  }) {
    if (_isExcellent(latency, packetLossPercent, signalStability)) {
      return NetworkQuality.excellent;
    }
    if (_isGood(latency, packetLossPercent, signalStability)) {
      return NetworkQuality.good;
    }
    if (_isAverage(latency, packetLossPercent, signalStability)) {
      return NetworkQuality.average;
    }

    return NetworkQuality.weak;
  }

  bool _isExcellent(
    Duration latency,
    double packetLossPercent,
    double signalStability,
  ) {
    return latency <= rules.excellentMaxLatency &&
        packetLossPercent <= rules.excellentMaxPacketLossPercent &&
        signalStability >= rules.excellentMinSignalStability;
  }

  bool _isGood(
    Duration latency,
    double packetLossPercent,
    double signalStability,
  ) {
    return latency <= rules.goodMaxLatency &&
        packetLossPercent <= rules.goodMaxPacketLossPercent &&
        signalStability >= rules.goodMinSignalStability;
  }

  bool _isAverage(
    Duration latency,
    double packetLossPercent,
    double signalStability,
  ) {
    return latency <= rules.averageMaxLatency &&
        packetLossPercent <= rules.averageMaxPacketLossPercent &&
        signalStability >= rules.averageMinSignalStability;
  }

  double _clampPercent(double value) {
    return value.clamp(0, 100).toDouble();
  }
}
