import 'smartsync_enums.dart';

class SyncDecision {
  final SyncAction action;
  final Duration waitDuration;
  final String reason;
  final bool shouldCompress;
  final bool isEmergency;

  const SyncDecision({
    required this.action,
    required this.reason,
    this.waitDuration = Duration.zero,
    this.shouldCompress = true,
    this.isEmergency = false,
  });

  const SyncDecision.sendNow({
    String reason = 'ready',
    bool shouldCompress = true,
  }) : this(
         action: SyncAction.sendNow,
         reason: reason,
         shouldCompress: shouldCompress,
       );

  const SyncDecision.sendNowCompressed({String reason = 'ready'})
    : this(action: SyncAction.sendNow, reason: reason, shouldCompress: true);

  const SyncDecision.emergencySend({String reason = 'emergency'})
    : this(
        action: SyncAction.emergencySend,
        reason: reason,
        shouldCompress: false,
        isEmergency: true,
      );

  const SyncDecision.queueOffline({String reason = 'offline'})
    : this(action: SyncAction.queueOffline, reason: reason);

  const SyncDecision.wait(Duration duration, {String reason = 'deferred'})
    : this(action: SyncAction.wait, waitDuration: duration, reason: reason);

  const SyncDecision.retry({String reason = 'retry'})
    : this(action: SyncAction.retry, reason: reason);

  const SyncDecision.drop({String reason = 'drop'})
    : this(action: SyncAction.drop, reason: reason);
}
