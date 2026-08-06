import 'package:esec_bus/smartsync/modules/retry/delivery_failure_type.dart';

class DeliveryRetryDecision {
  final bool shouldRetry;
  final bool shouldQueueOffline;
  final bool shouldDrop;
  final int nextRetryCount;
  final Duration retryDelay;
  final DeliveryFailureType failureType;
  final String reason;

  const DeliveryRetryDecision({
    required this.shouldRetry,
    required this.shouldQueueOffline,
    required this.shouldDrop,
    required this.nextRetryCount,
    required this.retryDelay,
    required this.failureType,
    required this.reason,
  });
}
