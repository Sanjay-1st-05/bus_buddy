import 'dart:async';

import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/network/network_measurement.dart';
import 'package:esec_bus/smartsync/modules/network/network_quality_classifier.dart';
import 'package:esec_bus/smartsync/modules/network/network_quality_rules.dart';

class NetworkIntelligenceModule implements SmartSyncNetworkMonitor {
  final NetworkQualityClassifier _classifier;
  final StreamController<NetworkStatus> _statusController;
  NetworkStatus _currentStatus;

  NetworkIntelligenceModule({
    NetworkQualityRules rules = const NetworkQualityRules.defaults(),
    NetworkStatus? initialStatus,
  }) : _classifier = NetworkQualityClassifier(rules: rules),
       _statusController = StreamController<NetworkStatus>.broadcast(),
       _currentStatus = initialStatus ?? _offlineStatus(DateTime.now());

  @override
  Stream<NetworkStatus> watchNetwork() => _statusController.stream;

  @override
  Future<NetworkStatus> currentStatus() async => _currentStatus;

  NetworkStatus recordMeasurement(NetworkMeasurement measurement) {
    final nextStatus = _classifier.classify(measurement);
    final changed = _hasStatusChange(_currentStatus, nextStatus);

    _currentStatus = nextStatus;
    if (changed && !_statusController.isClosed) {
      _statusController.add(nextStatus);
    }

    return nextStatus;
  }

  Future<void> dispose() async {
    await _statusController.close();
  }

  static NetworkStatus _offlineStatus(DateTime measuredAt) {
    return NetworkStatus(
      quality: NetworkQuality.offline,
      latency: Duration.zero,
      packetLossPercent: 100,
      signalStability: 0,
      measuredAt: measuredAt,
    );
  }

  bool _hasStatusChange(NetworkStatus previous, NetworkStatus next) {
    return previous.quality != next.quality ||
        previous.latency != next.latency ||
        previous.packetLossPercent != next.packetLossPercent ||
        previous.signalStability != next.signalStability;
  }
}
