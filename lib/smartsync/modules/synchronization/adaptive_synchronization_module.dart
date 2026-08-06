import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/synchronization/sync_schedule.dart';
import 'package:esec_bus/smartsync/modules/synchronization/synchronization_policy.dart';

class AdaptiveSynchronizationModule implements SmartSyncSynchronizationPlanner {
  final SynchronizationPolicy _policy;

  AdaptiveSynchronizationModule({required SmartSyncConfig config})
    : _policy = SynchronizationPolicy.fromIntervals(config.syncIntervals);

  const AdaptiveSynchronizationModule.withPolicy(SynchronizationPolicy policy)
    : _policy = policy;

  @override
  Duration intervalFor(NetworkStatus networkStatus) {
    return _policy.intervalFor(networkStatus.quality);
  }

  @override
  SyncSchedule plan({
    required NetworkStatus networkStatus,
    required DateTime now,
    DateTime? lastSyncedAt,
    bool isEmergency = false,
  }) {
    if (isEmergency) {
      return SyncSchedule(
        interval: _policy.emergencyInterval,
        shouldSyncNow: true,
        nextSyncAt: now,
        reason: 'emergency',
      );
    }

    if (networkStatus.quality == NetworkQuality.offline) {
      return const SyncSchedule(
        interval: Duration.zero,
        shouldSyncNow: false,
        nextSyncAt: null,
        reason: 'offline_queue_only',
      );
    }

    final interval = intervalFor(networkStatus);
    if (lastSyncedAt == null) {
      return SyncSchedule(
        interval: interval,
        shouldSyncNow: true,
        nextSyncAt: now,
        reason: 'first_sync',
      );
    }

    final nextSyncAt = lastSyncedAt.add(interval);
    final shouldSyncNow = !now.isBefore(nextSyncAt);

    return SyncSchedule(
      interval: interval,
      shouldSyncNow: shouldSyncNow,
      nextSyncAt: shouldSyncNow ? now : nextSyncAt,
      reason: shouldSyncNow ? 'interval_elapsed' : 'waiting_for_interval',
    );
  }
}
