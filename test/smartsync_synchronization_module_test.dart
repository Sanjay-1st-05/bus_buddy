import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('AdaptiveSynchronizationModule', () {
    final now = DateTime.utc(2026, 7, 11, 10);
    final module = AdaptiveSynchronizationModule(
      config: SmartSyncConfig.defaults(),
    );

    NetworkStatus status(NetworkQuality quality) {
      return NetworkStatus(
        quality: quality,
        latency: const Duration(milliseconds: 200),
        packetLossPercent: 1,
        signalStability: 0.9,
        measuredAt: now,
      );
    }

    test('uses configured intervals for each network quality', () {
      expect(
        module.intervalFor(status(NetworkQuality.excellent)),
        const Duration(seconds: 3),
      );
      expect(
        module.intervalFor(status(NetworkQuality.good)),
        const Duration(seconds: 5),
      );
      expect(
        module.intervalFor(status(NetworkQuality.average)),
        const Duration(seconds: 10),
      );
      expect(
        module.intervalFor(status(NetworkQuality.weak)),
        const Duration(seconds: 25),
      );
    });

    test('offline mode is queue-only and does not schedule backend sync', () {
      final schedule = module.plan(
        networkStatus: status(NetworkQuality.offline),
        now: now,
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
      );

      expect(schedule.interval, Duration.zero);
      expect(schedule.shouldSyncNow, isFalse);
      expect(schedule.nextSyncAt, isNull);
      expect(schedule.isQueueOnly, isTrue);
      expect(schedule.reason, 'offline_queue_only');
    });

    test('first valid network sync is due immediately', () {
      final schedule = module.plan(
        networkStatus: status(NetworkQuality.good),
        now: now,
      );

      expect(schedule.interval, const Duration(seconds: 5));
      expect(schedule.shouldSyncNow, isTrue);
      expect(schedule.nextSyncAt, now);
      expect(schedule.reason, 'first_sync');
    });

    test('waits until the active interval has elapsed', () {
      final schedule = module.plan(
        networkStatus: status(NetworkQuality.average),
        now: now,
        lastSyncedAt: now.subtract(const Duration(seconds: 4)),
      );

      expect(schedule.interval, const Duration(seconds: 10));
      expect(schedule.shouldSyncNow, isFalse);
      expect(schedule.nextSyncAt, now.add(const Duration(seconds: 6)));
      expect(schedule.reason, 'waiting_for_interval');
    });

    test('sync is due when the active interval has elapsed', () {
      final schedule = module.plan(
        networkStatus: status(NetworkQuality.average),
        now: now,
        lastSyncedAt: now.subtract(const Duration(seconds: 11)),
      );

      expect(schedule.shouldSyncNow, isTrue);
      expect(schedule.nextSyncAt, now);
      expect(schedule.reason, 'interval_elapsed');
    });

    test('emergency sync bypasses normal network interval timing', () {
      final schedule = module.plan(
        networkStatus: status(NetworkQuality.weak),
        now: now,
        lastSyncedAt: now,
        isEmergency: true,
      );

      expect(schedule.interval, Duration.zero);
      expect(schedule.shouldSyncNow, isTrue);
      expect(schedule.nextSyncAt, now);
      expect(schedule.reason, 'emergency');
    });
  });
}
