class OfflineQueueStats {
  final int pendingCount;
  final int syncingCount;
  final int failedCount;
  final int syncedCount;
  final int totalCount;
  final DateTime measuredAt;

  const OfflineQueueStats({
    required this.pendingCount,
    required this.syncingCount,
    required this.failedCount,
    required this.syncedCount,
    required this.totalCount,
    required this.measuredAt,
  });
}
