class RetryPolicy {
  final int maxRetryCount;
  final List<Duration> retryDelays;
  final Duration maxDelay;
  final bool queueOfflineAfterMaxRetries;

  const RetryPolicy({
    required this.maxRetryCount,
    required this.retryDelays,
    required this.maxDelay,
    required this.queueOfflineAfterMaxRetries,
  });

  const RetryPolicy.defaults()
    : maxRetryCount = 3,
      retryDelays = const [
        Duration(seconds: 2),
        Duration(seconds: 5),
        Duration(seconds: 10),
      ],
      maxDelay = const Duration(seconds: 30),
      queueOfflineAfterMaxRetries = true;

  Duration delayForAttempt(int nextAttempt) {
    if (nextAttempt <= 0) return Duration.zero;
    if (retryDelays.isEmpty) return Duration.zero;

    final index = nextAttempt - 1;
    final delay = index < retryDelays.length
        ? retryDelays[index]
        : retryDelays.last * (1 << (index - retryDelays.length + 1));

    return delay > maxDelay ? maxDelay : delay;
  }
}
