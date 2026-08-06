import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_cleanup_policy.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_item.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_stats.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_status.dart';

class InMemoryOfflineQueue implements SmartSyncOfflineQueue {
  final OfflineCleanupPolicy cleanupPolicy;
  final DateTime Function() _now;
  final List<OfflineQueueItem> _items = [];

  InMemoryOfflineQueue({
    this.cleanupPolicy = const OfflineCleanupPolicy.defaults(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  factory InMemoryOfflineQueue.fromConfig(
    SmartSyncConfig config, {
    DateTime Function()? now,
  }) {
    return InMemoryOfflineQueue(
      cleanupPolicy: OfflineCleanupPolicy(
        maxQueueSize: config.maxOfflineQueueSize,
        syncedRetention: const Duration(minutes: 5),
        failedRetention: const Duration(days: 1),
      ),
      now: now,
    );
  }

  @override
  Future<void> enqueue(SyncPacket packet) async {
    await enqueueItem(packet);
  }

  @override
  Future<OfflineQueueItem> enqueueItem(SyncPacket packet) async {
    final timestamp = _now();
    final existingIndex = _items.indexWhere(
      (item) => item.packetId == packet.packetId,
    );
    final item = OfflineQueueItem(
      packet: packet,
      status: OfflineQueueStatus.pending,
      queuedAt: timestamp,
      updatedAt: timestamp,
      attemptCount: 0,
    );

    if (existingIndex >= 0) {
      _items[existingIndex] = item;
    } else {
      _items.add(item);
    }

    _trimToMaxSize();
    return item;
  }

  @override
  Future<List<SyncPacket>> readBatch({required int limit}) async {
    final items = await readItems(limit: limit);
    return items.map((item) => item.packet).toList(growable: false);
  }

  @override
  Future<List<OfflineQueueItem>> readItems({required int limit}) async {
    if (limit <= 0) return const [];

    final pendingItems =
        _items
            .where((item) => item.status == OfflineQueueStatus.pending)
            .toList(growable: false)
          ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    return pendingItems.take(limit).toList(growable: false);
  }

  @override
  Future<void> markSyncing(String packetId) async {
    _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.syncing,
        updatedAt: _now(),
        attemptCount: item.attemptCount + 1,
        clearLastError: true,
      );
    });
  }

  @override
  Future<void> markSynced(String packetId) async {
    _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.synced,
        updatedAt: _now(),
        clearLastError: true,
      );
    });
  }

  @override
  Future<void> markFailed(String packetId, String error) async {
    _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.failed,
        updatedAt: _now(),
        lastError: error,
      );
    });
  }

  @override
  Future<void> requeueFailed(String packetId) async {
    _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.pending,
        updatedAt: _now(),
        clearLastError: true,
      );
    });
  }

  @override
  Future<void> cleanup() async {
    final timestamp = _now();
    _items.removeWhere((item) {
      final age = timestamp.difference(item.updatedAt);
      if (item.status == OfflineQueueStatus.synced) {
        return age >= cleanupPolicy.syncedRetention;
      }
      if (item.status == OfflineQueueStatus.failed) {
        return age >= cleanupPolicy.failedRetention;
      }
      return false;
    });
    _trimToMaxSize();
  }

  @override
  Future<int> size() async => _items.length;

  @override
  Future<OfflineQueueStats> stats() async {
    final pending = _items
        .where((item) => item.status == OfflineQueueStatus.pending)
        .length;
    final syncing = _items
        .where((item) => item.status == OfflineQueueStatus.syncing)
        .length;
    final failed = _items
        .where((item) => item.status == OfflineQueueStatus.failed)
        .length;
    final synced = _items
        .where((item) => item.status == OfflineQueueStatus.synced)
        .length;

    return OfflineQueueStats(
      pendingCount: pending,
      syncingCount: syncing,
      failedCount: failed,
      syncedCount: synced,
      totalCount: _items.length,
      measuredAt: _now(),
    );
  }

  void _update(
    String packetId,
    OfflineQueueItem Function(OfflineQueueItem) map,
  ) {
    final index = _items.indexWhere((item) => item.packetId == packetId);
    if (index < 0) return;
    _items[index] = map(_items[index]);
  }

  void _trimToMaxSize() {
    final overflow = _items.length - cleanupPolicy.maxQueueSize;
    if (overflow <= 0) return;

    _items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    _items.removeRange(0, overflow);
  }
}
