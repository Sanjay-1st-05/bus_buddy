import 'dart:async';
import 'dart:io';

import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/modules/network/network_intelligence_module.dart';
import 'package:esec_bus/smartsync/modules/network/network_measurement.dart';

typedef NetworkProbe =
    Future<void> Function(String host, int port, Duration timeout);

class RuntimeNetworkMonitor implements SmartSyncNetworkMonitor {
  final NetworkIntelligenceModule _networkModule;
  final NetworkProbe _probe;
  final String probeHost;
  final int probePort;
  final Duration probeInterval;
  final Duration probeTimeout;
  final int stabilityWindowSize;
  final List<_NetworkProbeResult> _recentResults = <_NetworkProbeResult>[];

  Timer? _timer;
  bool _isProbing = false;

  RuntimeNetworkMonitor({
    NetworkIntelligenceModule? networkModule,
    NetworkProbe? probe,
    this.probeHost = 'clients3.google.com',
    this.probePort = 443,
    this.probeInterval = const Duration(seconds: 5),
    this.probeTimeout = const Duration(seconds: 3),
    this.stabilityWindowSize = 8,
  }) : _networkModule = networkModule ?? NetworkIntelligenceModule(),
       _probe = probe ?? _defaultProbe;

  void start({bool probeImmediately = true}) {
    if (_timer != null) {
      return;
    }

    if (probeImmediately) {
      unawaited(refresh());
    }

    _timer = Timer.periodic(probeInterval, (_) => unawaited(refresh()));
  }

  Future<NetworkStatus> refresh() async {
    if (_isProbing) {
      return currentStatus();
    }

    _isProbing = true;
    final stopwatch = Stopwatch()..start();
    var isConnected = false;

    try {
      await _probe(probeHost, probePort, probeTimeout).timeout(probeTimeout);
      isConnected = true;
    } on Object {
      isConnected = false;
    } finally {
      stopwatch.stop();
    }

    final latency = isConnected ? stopwatch.elapsed : probeTimeout;
    _rememberProbe(_NetworkProbeResult(isConnected, latency));

    final measurement = NetworkMeasurement(
      isConnected: isConnected,
      latency: latency,
      packetLossPercent: _packetLossPercent(),
      signalStability: _signalStability(),
      measuredAt: DateTime.now(),
      source: 'runtime:$probeHost:$probePort',
    );

    _isProbing = false;
    return _networkModule.recordMeasurement(measurement);
  }

  @override
  Future<NetworkStatus> currentStatus() => _networkModule.currentStatus();

  @override
  Stream<NetworkStatus> watchNetwork() => _networkModule.watchNetwork();

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _networkModule.dispose();
  }

  static Future<void> _defaultProbe(
    String host,
    int port,
    Duration timeout,
  ) async {
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw const SocketException('Network probe host did not resolve');
    }

    final socket = await Socket.connect(
      addresses.first,
      port,
      timeout: timeout,
    );
    socket.destroy();
  }

  void _rememberProbe(_NetworkProbeResult result) {
    _recentResults.add(result);
    if (_recentResults.length > stabilityWindowSize) {
      _recentResults.removeAt(0);
    }
  }

  double _packetLossPercent() {
    if (_recentResults.isEmpty) {
      return 100;
    }

    final failures = _recentResults.where((result) => !result.isConnected);
    return (failures.length / _recentResults.length) * 100;
  }

  double _signalStability() {
    if (_recentResults.isEmpty) {
      return 0;
    }

    final successfulResults = _recentResults
        .where((result) => result.isConnected)
        .toList(growable: false);
    final successRatio = successfulResults.length / _recentResults.length;
    if (successfulResults.length < 2) {
      return successRatio;
    }

    final averageLatency =
        successfulResults
            .map((result) => result.latency.inMilliseconds)
            .reduce((total, latency) => total + latency) /
        successfulResults.length;
    if (averageLatency <= 0) {
      return successRatio;
    }

    final averageDeviation =
        successfulResults
            .map(
              (result) =>
                  (result.latency.inMilliseconds - averageLatency).abs(),
            )
            .reduce((total, deviation) => total + deviation) /
        successfulResults.length;
    final latencyConsistency = (1 - (averageDeviation / averageLatency))
        .clamp(0, 1)
        .toDouble();

    return (successRatio * latencyConsistency).clamp(0, 1).toDouble();
  }
}

class _NetworkProbeResult {
  final bool isConnected;
  final Duration latency;

  const _NetworkProbeResult(this.isConnected, this.latency);
}
