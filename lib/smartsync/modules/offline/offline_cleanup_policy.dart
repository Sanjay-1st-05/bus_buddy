class OfflineCleanupPolicy {
  final int maxQueueSize;
  final Duration syncedRetention;
  final Duration failedRetention;

  const OfflineCleanupPolicy({
    required this.maxQueueSize,
    required this.syncedRetention,
    required this.failedRetention,
  });

  const OfflineCleanupPolicy.defaults()
    : maxQueueSize = 1000,
      syncedRetention = const Duration(minutes: 5),
      failedRetention = const Duration(days: 1);
}
