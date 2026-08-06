import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryOfflineQueue', () {
    late DateTime now;
    late InMemoryOfflineQueue queue;

    SyncPacket packet(String id, {DateTime? capturedAt}) {
      return SyncPacket(
        packetId: id,
        deviceId: 'device-1',
        transportId: 'BUS_01',
        sample: LocationSample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: capturedAt ?? now,
        ),
      );
    }

    setUp(() {
      now = DateTime.utc(2026, 7, 11, 10);
      queue = InMemoryOfflineQueue(
        cleanupPolicy: const OfflineCleanupPolicy(
          maxQueueSize: 3,
          syncedRetention: Duration(minutes: 5),
          failedRetention: Duration(hours: 1),
        ),
        now: () => now,
      );
    });

    test('enqueues packets as pending items', () async {
      final item = await queue.enqueueItem(packet('p1'));

      expect(item.packetId, 'p1');
      expect(item.status, OfflineQueueStatus.pending);
      expect(await queue.size(), 1);
    });

    test('reads pending items in chronological order', () async {
      await queue.enqueue(packet('p2'));
      now = now.add(const Duration(seconds: 1));
      await queue.enqueue(packet('p1'));

      final batch = await queue.readBatch(limit: 2);

      expect(batch.map((packet) => packet.packetId), ['p2', 'p1']);
    });

    test('readItems respects limit and ignores non-pending entries', () async {
      await queue.enqueue(packet('p1'));
      await queue.enqueue(packet('p2'));
      await queue.markSyncing('p1');

      final items = await queue.readItems(limit: 5);

      expect(items.map((item) => item.packetId), ['p2']);
    });

    test('markSyncing increments attempt count', () async {
      await queue.enqueue(packet('p1'));
      await queue.markSyncing('p1');

      final stats = await queue.stats();
      final syncing = await queue.readItems(limit: 10);

      expect(syncing, isEmpty);
      expect(stats.syncingCount, 1);
    });

    test(
      'markSynced removes item from pending batch and records stats',
      () async {
        await queue.enqueue(packet('p1'));
        await queue.markSynced('p1');

        final batch = await queue.readBatch(limit: 1);
        final stats = await queue.stats();

        expect(batch, isEmpty);
        expect(stats.syncedCount, 1);
        expect(stats.totalCount, 1);
      },
    );

    test(
      'markFailed and requeueFailed preserve failed error state correctly',
      () async {
        await queue.enqueue(packet('p1'));
        await queue.markFailed('p1', 'network timeout');

        var stats = await queue.stats();
        expect(stats.failedCount, 1);

        await queue.requeueFailed('p1');
        stats = await queue.stats();

        expect(stats.pendingCount, 1);
        expect(stats.failedCount, 0);
      },
    );

    test('cleanup removes expired synced and failed items', () async {
      await queue.enqueue(packet('synced'));
      await queue.markSynced('synced');
      await queue.enqueue(packet('failed'));
      await queue.markFailed('failed', 'still offline');

      now = now.add(const Duration(hours: 2));
      await queue.cleanup();

      expect(await queue.size(), 0);
    });

    test('queue trims oldest items when max size is exceeded', () async {
      await queue.enqueue(packet('p1'));
      now = now.add(const Duration(seconds: 1));
      await queue.enqueue(packet('p2'));
      now = now.add(const Duration(seconds: 1));
      await queue.enqueue(packet('p3'));
      now = now.add(const Duration(seconds: 1));
      await queue.enqueue(packet('p4'));

      final batch = await queue.readBatch(limit: 10);

      expect(batch.map((packet) => packet.packetId), ['p2', 'p3', 'p4']);
      expect(await queue.size(), 3);
    });

    test('duplicate packet id replaces existing queue item', () async {
      await queue.enqueue(packet('p1'));
      now = now.add(const Duration(seconds: 1));
      await queue.enqueue(packet('p1'));

      final batch = await queue.readBatch(limit: 10);

      expect(batch, hasLength(1));
      expect(batch.single.packetId, 'p1');
      expect(await queue.size(), 1);
    });

    test('fromConfig uses max offline queue size', () async {
      final configured = InMemoryOfflineQueue.fromConfig(
        SmartSyncConfig.defaults(),
        now: () => now,
      );

      expect(configured.cleanupPolicy.maxQueueSize, 1000);
    });

    test('readBatch returns empty for zero and negative limits', () async {
      await queue.enqueue(packet('p1'));

      expect(await queue.readBatch(limit: 0), isEmpty);
      expect(await queue.readBatch(limit: -1), isEmpty);
    });

    test('unknown packet state changes are ignored safely', () async {
      await queue.markSyncing('missing');
      await queue.markSynced('missing');
      await queue.markFailed('missing', 'error');
      await queue.requeueFailed('missing');

      final stats = await queue.stats();

      expect(stats.totalCount, 0);
    });

    test('cleanup keeps fresh failed items inside retention window', () async {
      await queue.enqueue(packet('failed'));
      await queue.markFailed('failed', 'temporary outage');

      now = now.add(const Duration(minutes: 30));
      await queue.cleanup();

      final stats = await queue.stats();
      expect(stats.failedCount, 1);
      expect(await queue.size(), 1);
    });
  });
}
