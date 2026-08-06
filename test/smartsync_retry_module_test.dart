import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('uses configured retry delays and caps later exponential delays', () {
      const policy = RetryPolicy(
        maxRetryCount: 5,
        retryDelays: [
          Duration(seconds: 2),
          Duration(seconds: 5),
          Duration(seconds: 10),
        ],
        maxDelay: Duration(seconds: 30),
        queueOfflineAfterMaxRetries: true,
      );

      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 5));
      expect(policy.delayForAttempt(3), const Duration(seconds: 10));
      expect(policy.delayForAttempt(4), const Duration(seconds: 20));
      expect(policy.delayForAttempt(5), const Duration(seconds: 30));
    });
  });

  group('ReliableDeliveryModule', () {
    const module = ReliableDeliveryModule();
    final now = DateTime.utc(2026, 7, 11, 10);

    NetworkStatus network(NetworkQuality quality) {
      return NetworkStatus(
        quality: quality,
        latency: const Duration(milliseconds: 200),
        packetLossPercent: 1,
        signalStability: 0.9,
        measuredAt: now,
      );
    }

    SyncResult result({required bool success, required int statusCode}) {
      return SyncResult(
        success: success,
        statusCode: statusCode,
        completedAt: now,
      );
    }

    test('successful delivery clears retry state', () {
      final decision = module.decide(
        result: result(success: true, statusCode: 200),
        networkStatus: network(NetworkQuality.good),
        currentRetryCount: 2,
      );

      expect(decision.shouldRetry, isFalse);
      expect(decision.shouldQueueOffline, isFalse);
      expect(decision.shouldDrop, isFalse);
      expect(decision.nextRetryCount, 0);
      expect(decision.reason, 'delivery_success');
    });

    test('offline network queues packet immediately', () {
      final decision = module.decide(
        result: result(success: false, statusCode: 0),
        networkStatus: network(NetworkQuality.offline),
        currentRetryCount: 1,
      );

      expect(decision.shouldRetry, isFalse);
      expect(decision.shouldQueueOffline, isTrue);
      expect(decision.failureType, DeliveryFailureType.networkUnavailable);
      expect(decision.reason, 'network_offline');
    });

    test('server failure schedules retry with backoff', () {
      final decision = module.decide(
        result: result(success: false, statusCode: 500),
        networkStatus: network(NetworkQuality.good),
        currentRetryCount: 1,
      );

      expect(decision.shouldRetry, isTrue);
      expect(decision.nextRetryCount, 2);
      expect(decision.retryDelay, const Duration(seconds: 5));
      expect(decision.failureType, DeliveryFailureType.serverError);
      expect(decision.reason, 'retry_scheduled');
    });

    test('rate limit failure remains retryable', () {
      final decision = module.decide(
        result: result(success: false, statusCode: 429),
        networkStatus: network(NetworkQuality.good),
        currentRetryCount: 0,
      );

      expect(decision.shouldRetry, isTrue);
      expect(decision.retryDelay, const Duration(seconds: 2));
      expect(decision.failureType, DeliveryFailureType.rateLimited);
    });

    test('bad request and unauthorized failures are dropped', () {
      final badRequest = module.decide(
        result: result(success: false, statusCode: 400),
        networkStatus: network(NetworkQuality.good),
        currentRetryCount: 0,
      );
      final unauthorized = module.decide(
        result: result(success: false, statusCode: 401),
        networkStatus: network(NetworkQuality.good),
        currentRetryCount: 0,
      );

      expect(badRequest.shouldDrop, isTrue);
      expect(badRequest.failureType, DeliveryFailureType.badRequest);
      expect(unauthorized.shouldDrop, isTrue);
      expect(unauthorized.failureType, DeliveryFailureType.unauthorized);
    });

    test('max retries exhausted queues packet offline', () {
      final decision = module.decide(
        result: result(success: false, statusCode: 503),
        networkStatus: network(NetworkQuality.weak),
        currentRetryCount: 3,
      );

      expect(decision.shouldRetry, isFalse);
      expect(decision.shouldQueueOffline, isTrue);
      expect(decision.shouldDrop, isFalse);
      expect(decision.reason, 'max_retries_exhausted');
    });

    test('classifies common delivery failures', () {
      expect(
        module.classifyFailure(result(success: false, statusCode: 0)),
        DeliveryFailureType.networkUnavailable,
      );
      expect(
        module.classifyFailure(result(success: false, statusCode: 408)),
        DeliveryFailureType.timeout,
      );
      expect(
        module.classifyFailure(result(success: false, statusCode: 422)),
        DeliveryFailureType.badRequest,
      );
      expect(
        module.classifyFailure(result(success: false, statusCode: 502)),
        DeliveryFailureType.serverError,
      );
      expect(
        module.classifyFailure(result(success: false, statusCode: 418)),
        DeliveryFailureType.unknown,
      );
    });
  });
}
