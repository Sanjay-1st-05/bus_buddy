import 'package:esec_bus/smartsync/models/sync_decision.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_event.dart';

class EmergencySyncResult {
  final EmergencyEvent event;
  final SyncDecision decision;
  final int maxRetryCount;
  final List<Duration> retryDelays;
  final bool shouldBypassNormalInterval;
  final bool shouldBypassCompression;
  final String reason;

  const EmergencySyncResult({
    required this.event,
    required this.decision,
    required this.maxRetryCount,
    required this.retryDelays,
    required this.shouldBypassNormalInterval,
    required this.shouldBypassCompression,
    required this.reason,
  });
}
