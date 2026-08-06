class SyncSchedule {
  final Duration interval;
  final bool shouldSyncNow;
  final DateTime? nextSyncAt;
  final String reason;

  const SyncSchedule({
    required this.interval,
    required this.shouldSyncNow,
    required this.nextSyncAt,
    required this.reason,
  });

  bool get isQueueOnly => interval == Duration.zero && !shouldSyncNow;
}
