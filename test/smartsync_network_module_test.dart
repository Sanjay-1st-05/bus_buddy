import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('NetworkQualityClassifier', () {
    final classifier = NetworkQualityClassifier();
    final measuredAt = DateTime.utc(2026, 7, 11);

    test('classifies offline measurements explicitly', () {
      final status = classifier.classify(
        NetworkMeasurement(
          isConnected: false,
          latency: const Duration(milliseconds: 200),
          packetLossPercent: 0,
          signalStability: 1,
          measuredAt: measuredAt,
        ),
      );

      expect(status.quality, NetworkQuality.offline);
      expect(status.isOffline, isTrue);
      expect(status.packetLossPercent, 100);
      expect(status.signalStability, 0);
    });

    test('classifies excellent, good, average, and weak networks', () {
      NetworkStatus classify({
        required Duration latency,
        required double packetLoss,
        required double stability,
      }) {
        return classifier.classify(
          NetworkMeasurement(
            isConnected: true,
            latency: latency,
            packetLossPercent: packetLoss,
            signalStability: stability,
            measuredAt: measuredAt,
          ),
        );
      }

      expect(
        classify(
          latency: const Duration(milliseconds: 100),
          packetLoss: 0,
          stability: 0.95,
        ).quality,
        NetworkQuality.excellent,
      );
      expect(
        classify(
          latency: const Duration(milliseconds: 300),
          packetLoss: 2,
          stability: 0.8,
        ).quality,
        NetworkQuality.good,
      );
      expect(
        classify(
          latency: const Duration(milliseconds: 900),
          packetLoss: 7,
          stability: 0.55,
        ).quality,
        NetworkQuality.average,
      );
      expect(
        classify(
          latency: const Duration(milliseconds: 1800),
          packetLoss: 20,
          stability: 0.2,
        ).quality,
        NetworkQuality.weak,
      );
    });

    test('normalizes invalid packet loss, stability, and latency inputs', () {
      final status = classifier.classify(
        NetworkMeasurement(
          isConnected: true,
          latency: const Duration(milliseconds: -10),
          packetLossPercent: -50,
          signalStability: 2,
          measuredAt: measuredAt,
        ),
      );

      expect(status.latency, Duration.zero);
      expect(status.packetLossPercent, 0);
      expect(status.signalStability, 1);
      expect(status.quality, NetworkQuality.excellent);
    });
  });

  group('NetworkIntelligenceModule', () {
    test('stores the latest status for Decision Engine reads', () async {
      final module = NetworkIntelligenceModule(
        initialStatus: NetworkStatus(
          quality: NetworkQuality.offline,
          latency: Duration.zero,
          packetLossPercent: 100,
          signalStability: 0,
          measuredAt: DateTime.utc(2026),
        ),
      );

      final status = module.recordMeasurement(
        NetworkMeasurement(
          isConnected: true,
          latency: const Duration(milliseconds: 300),
          packetLossPercent: 2,
          signalStability: 0.8,
          measuredAt: DateTime.utc(2026, 7, 11),
        ),
      );

      expect(status.quality, NetworkQuality.good);
      expect((await module.currentStatus()).quality, NetworkQuality.good);

      await module.dispose();
    });

    test('emits events only when network status changes', () async {
      final module = NetworkIntelligenceModule(
        initialStatus: NetworkStatus(
          quality: NetworkQuality.offline,
          latency: Duration.zero,
          packetLossPercent: 100,
          signalStability: 0,
          measuredAt: DateTime.utc(2026),
        ),
      );
      final emittedStatuses = <NetworkStatus>[];
      final subscription = module.watchNetwork().listen(emittedStatuses.add);

      module
        ..recordMeasurement(
          NetworkMeasurement(
            isConnected: false,
            latency: Duration.zero,
            packetLossPercent: 100,
            signalStability: 0,
            measuredAt: DateTime.utc(2026, 7, 11, 10),
          ),
        )
        ..recordMeasurement(
          NetworkMeasurement(
            isConnected: true,
            latency: const Duration(milliseconds: 90),
            packetLossPercent: 0,
            signalStability: 0.95,
            measuredAt: DateTime.utc(2026, 7, 11, 10, 1),
          ),
        );

      await Future<void>.delayed(Duration.zero);

      expect(emittedStatuses, hasLength(1));
      expect(emittedStatuses.single.quality, NetworkQuality.excellent);

      await subscription.cancel();
      await module.dispose();
    });
  });

  group('RuntimeNetworkMonitor', () {
    test('feeds successful runtime probes into network intelligence', () async {
      final monitor = RuntimeNetworkMonitor(
        probe: (_, _, _) async {},
        probeTimeout: const Duration(seconds: 1),
      );

      final status = await monitor.refresh();

      expect(status.isOffline, isFalse);
      expect(status.packetLossPercent, 0);
      expect(status.signalStability, 1);
      expect((await monitor.currentStatus()).quality, status.quality);

      await monitor.dispose();
    });

    test('records failed runtime probes as offline measurements', () async {
      final monitor = RuntimeNetworkMonitor(
        probe: (_, _, _) => Future<void>.error(Exception('offline')),
        probeTimeout: const Duration(milliseconds: 100),
      );

      final status = await monitor.refresh();

      expect(status.quality, NetworkQuality.offline);
      expect(status.packetLossPercent, 100);
      expect(status.signalStability, 0);

      await monitor.dispose();
    });

    test('calculates packet loss over the recent probe window', () async {
      var attempt = 0;
      final monitor = RuntimeNetworkMonitor(
        stabilityWindowSize: 2,
        probeTimeout: const Duration(milliseconds: 100),
        probe: (_, _, _) {
          attempt += 1;
          if (attempt.isOdd) {
            return Future<void>.error(Exception('offline'));
          }
          return Future<void>.value();
        },
      );

      await monitor.refresh();
      final status = await monitor.refresh();

      expect(status.isOffline, isFalse);
      expect(status.packetLossPercent, 50);

      await monitor.dispose();
    });

    test('does not run overlapping refresh probes', () async {
      var probeCount = 0;
      final monitor = RuntimeNetworkMonitor(
        probeTimeout: const Duration(seconds: 1),
        probe: (_, _, _) async {
          probeCount += 1;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
      );

      final first = monitor.refresh();
      final second = await monitor.refresh();
      final firstStatus = await first;

      expect(probeCount, 1);
      expect(second.quality, NetworkQuality.offline);
      expect(firstStatus.isOffline, isFalse);

      await monitor.dispose();
    });

    test(
      'reduces stability when successful probes have volatile latency',
      () async {
        var attempt = 0;
        final monitor = RuntimeNetworkMonitor(
          stabilityWindowSize: 3,
          probe: (_, _, _) async {
            attempt += 1;
            if (attempt == 2) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
          },
        );

        await monitor.refresh();
        await monitor.refresh();
        final status = await monitor.refresh();

        expect(status.isOffline, isFalse);
        expect(status.packetLossPercent, 0);
        expect(status.signalStability, lessThan(1));

        await monitor.dispose();
      },
    );
  });
}
