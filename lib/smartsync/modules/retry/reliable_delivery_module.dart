import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/models/sync_result.dart';
import 'package:esec_bus/smartsync/modules/retry/delivery_failure_type.dart';
import 'package:esec_bus/smartsync/modules/retry/delivery_retry_decision.dart';
import 'package:esec_bus/smartsync/modules/retry/retry_policy.dart';

class ReliableDeliveryModule implements SmartSyncReliableDeliveryPlanner {
  final RetryPolicy policy;

  const ReliableDeliveryModule({this.policy = const RetryPolicy.defaults()});

  factory ReliableDeliveryModule.fromConfig(SmartSyncConfig config) {
    return ReliableDeliveryModule(
      policy: RetryPolicy(
        maxRetryCount: config.maxRetryCount,
        retryDelays: const [
          Duration(seconds: 2),
          Duration(seconds: 5),
          Duration(seconds: 10),
        ],
        maxDelay: const Duration(seconds: 30),
        queueOfflineAfterMaxRetries: true,
      ),
    );
  }

  @override
  DeliveryRetryDecision decide({
    required SyncResult result,
    required NetworkStatus networkStatus,
    required int currentRetryCount,
  }) {
    if (result.success) {
      return const DeliveryRetryDecision(
        shouldRetry: false,
        shouldQueueOffline: false,
        shouldDrop: false,
        nextRetryCount: 0,
        retryDelay: Duration.zero,
        failureType: DeliveryFailureType.none,
        reason: 'delivery_success',
      );
    }

    if (networkStatus.quality == NetworkQuality.offline) {
      return _queueOffline(
        currentRetryCount: currentRetryCount,
        failureType: DeliveryFailureType.networkUnavailable,
        reason: 'network_offline',
      );
    }

    final failureType = classifyFailure(result);

    if (_shouldDrop(failureType)) {
      return DeliveryRetryDecision(
        shouldRetry: false,
        shouldQueueOffline: false,
        shouldDrop: true,
        nextRetryCount: currentRetryCount,
        retryDelay: Duration.zero,
        failureType: failureType,
        reason: 'non_retryable_failure',
      );
    }

    if (currentRetryCount >= policy.maxRetryCount) {
      if (policy.queueOfflineAfterMaxRetries) {
        return _queueOffline(
          currentRetryCount: currentRetryCount,
          failureType: failureType,
          reason: 'max_retries_exhausted',
        );
      }

      return DeliveryRetryDecision(
        shouldRetry: false,
        shouldQueueOffline: false,
        shouldDrop: true,
        nextRetryCount: currentRetryCount,
        retryDelay: Duration.zero,
        failureType: failureType,
        reason: 'max_retries_exhausted_drop',
      );
    }

    final nextRetryCount = currentRetryCount + 1;

    return DeliveryRetryDecision(
      shouldRetry: true,
      shouldQueueOffline: false,
      shouldDrop: false,
      nextRetryCount: nextRetryCount,
      retryDelay: policy.delayForAttempt(nextRetryCount),
      failureType: failureType,
      reason: 'retry_scheduled',
    );
  }

  @override
  DeliveryFailureType classifyFailure(SyncResult result) {
    if (result.success) return DeliveryFailureType.none;

    final statusCode = result.statusCode;
    if (statusCode == 0) return DeliveryFailureType.networkUnavailable;
    if (statusCode == 408) return DeliveryFailureType.timeout;
    if (statusCode == 401 || statusCode == 403) {
      return DeliveryFailureType.unauthorized;
    }
    if (statusCode == 400 || statusCode == 422) {
      return DeliveryFailureType.badRequest;
    }
    if (statusCode == 429) return DeliveryFailureType.rateLimited;
    if (statusCode >= 500 && statusCode <= 599) {
      return DeliveryFailureType.serverError;
    }

    return DeliveryFailureType.unknown;
  }

  bool _shouldDrop(DeliveryFailureType failureType) {
    return failureType == DeliveryFailureType.unauthorized ||
        failureType == DeliveryFailureType.badRequest;
  }

  DeliveryRetryDecision _queueOffline({
    required int currentRetryCount,
    required DeliveryFailureType failureType,
    required String reason,
  }) {
    return DeliveryRetryDecision(
      shouldRetry: false,
      shouldQueueOffline: true,
      shouldDrop: false,
      nextRetryCount: currentRetryCount,
      retryDelay: Duration.zero,
      failureType: failureType,
      reason: reason,
    );
  }
}
