import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_cleanup_policy.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_item.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_stats.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_status.dart';

class SharedPreferencesOfflineQueue implements SmartSyncOfflineQueue {
  static const String _storageKey = 'smartsync.offline_queue.v1';

  final OfflineCleanupPolicy cleanupPolicy;
  final DateTime Function() _now;

  const SharedPreferencesOfflineQueue({
    this.cleanupPolicy = const OfflineCleanupPolicy.defaults(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  factory SharedPreferencesOfflineQueue.fromConfig(
    SmartSyncConfig config, {
    DateTime Function()? now,
  }) {
    return SharedPreferencesOfflineQueue(
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
    final items = await _load();
    final timestamp = _now();
    final item = OfflineQueueItem(
      packet: packet,
      status: OfflineQueueStatus.pending,
      queuedAt: timestamp,
      updatedAt: timestamp,
      attemptCount: 0,
    );
    final existingIndex = items.indexWhere(
      (entry) => entry.packetId == packet.packetId,
    );

    if (existingIndex >= 0) {
      items[existingIndex] = item;
    } else {
      items.add(item);
    }

    await _save(_trimToMaxSize(items));
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

    final items = await _load();
    final pending =
        items
            .where((item) => item.status == OfflineQueueStatus.pending)
            .toList(growable: false)
          ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    return pending.take(limit).toList(growable: false);
  }

  @override
  Future<void> markSyncing(String packetId) async {
    await _update(packetId, (item) {
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
    await _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.synced,
        updatedAt: _now(),
        clearLastError: true,
      );
    });
  }

  @override
  Future<void> markFailed(String packetId, String error) async {
    await _update(packetId, (item) {
      return item.copyWith(
        status: OfflineQueueStatus.failed,
        updatedAt: _now(),
        lastError: error,
      );
    });
  }

  @override
  Future<void> requeueFailed(String packetId) async {
    await _update(packetId, (item) {
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
    final items = await _load();
    items.removeWhere((item) {
      final age = timestamp.difference(item.updatedAt);
      if (item.status == OfflineQueueStatus.synced) {
        return age >= cleanupPolicy.syncedRetention;
      }
      if (item.status == OfflineQueueStatus.failed) {
        return age >= cleanupPolicy.failedRetention;
      }
      return false;
    });
    await _save(_trimToMaxSize(items));
  }

  @override
  Future<int> size() async => (await _load()).length;

  @override
  Future<OfflineQueueStats> stats() async {
    final items = await _load();
    final pending = items
        .where((item) => item.status == OfflineQueueStatus.pending)
        .length;
    final syncing = items
        .where((item) => item.status == OfflineQueueStatus.syncing)
        .length;
    final failed = items
        .where((item) => item.status == OfflineQueueStatus.failed)
        .length;
    final synced = items
        .where((item) => item.status == OfflineQueueStatus.synced)
        .length;

    return OfflineQueueStats(
      pendingCount: pending,
      syncingCount: syncing,
      failedCount: failed,
      syncedCount: synced,
      totalCount: items.length,
      measuredAt: _now(),
    );
  }

  Future<void> _update(
    String packetId,
    OfflineQueueItem Function(OfflineQueueItem) map,
  ) async {
    final items = await _load();
    final index = items.indexWhere((item) => item.packetId == packetId);
    if (index < 0) return;
    items[index] = map(items[index]);
    await _save(items);
  }

  List<OfflineQueueItem> _trimToMaxSize(List<OfflineQueueItem> items) {
    final overflow = items.length - cleanupPolicy.maxQueueSize;
    if (overflow <= 0) return items;

    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    items.removeRange(0, overflow);
    return items;
  }

  Future<List<OfflineQueueItem>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];

    return raw
        .map(_decodeItem)
        .whereType<OfflineQueueItem>()
        .toList(growable: true);
  }

  Future<void> _save(List<OfflineQueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      items.map(_encodeItem).toList(growable: false),
    );
  }

  String _encodeItem(OfflineQueueItem item) {
    return jsonEncode({
      'packet': _encodePacket(item.packet),
      'status': item.status.name,
      'queuedAt': item.queuedAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
      'attemptCount': item.attemptCount,
      'lastError': item.lastError,
    });
  }

  OfflineQueueItem? _decodeItem(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      final packet = _decodePacket(data['packet']);
      if (packet == null) return null;

      return OfflineQueueItem(
        packet: packet,
        status: _statusFromName(data['status']),
        queuedAt: DateTime.parse(data['queuedAt'] as String),
        updatedAt: DateTime.parse(data['updatedAt'] as String),
        attemptCount: data['attemptCount'] as int? ?? 0,
        lastError: data['lastError'] as String?,
      );
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> _encodePacket(SyncPacket packet) {
    return {
      'packetId': packet.packetId,
      'deviceId': packet.deviceId,
      'transportId': packet.transportId,
      'sample': {
        'latitude': packet.sample.latitude,
        'longitude': packet.sample.longitude,
        'speedMetersPerSecond': packet.sample.speedMetersPerSecond,
        'headingDegrees': packet.sample.headingDegrees,
        'accuracyMeters': packet.sample.accuracyMeters,
        'capturedAt': packet.sample.capturedAt.toIso8601String(),
      },
      'metadata': packet.metadata,
    };
  }

  SyncPacket? _decodePacket(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final sample = raw['sample'];
    if (sample is! Map<String, dynamic>) return null;

    return SyncPacket(
      packetId: raw['packetId'] as String,
      deviceId: raw['deviceId'] as String,
      transportId: raw['transportId'] as String,
      sample: LocationSample(
        latitude: (sample['latitude'] as num).toDouble(),
        longitude: (sample['longitude'] as num).toDouble(),
        speedMetersPerSecond:
            (sample['speedMetersPerSecond'] as num?)?.toDouble(),
        headingDegrees: (sample['headingDegrees'] as num?)?.toDouble(),
        accuracyMeters: (sample['accuracyMeters'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(sample['capturedAt'] as String),
      ),
      metadata: Map<String, dynamic>.from(
        raw['metadata'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  OfflineQueueStatus _statusFromName(Object? name) {
    return OfflineQueueStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => OfflineQueueStatus.pending,
    );
  }
}
