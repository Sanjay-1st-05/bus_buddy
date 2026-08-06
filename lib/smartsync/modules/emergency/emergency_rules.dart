class EmergencyRules {
  final bool emergencyPriorityEnabled;
  final int aggressiveRetryCount;
  final List<Duration> aggressiveRetryDelays;
  final bool bypassCompression;
  final bool bypassSyncInterval;

  const EmergencyRules({
    required this.emergencyPriorityEnabled,
    required this.aggressiveRetryCount,
    required this.aggressiveRetryDelays,
    required this.bypassCompression,
    required this.bypassSyncInterval,
  });

  const EmergencyRules.defaults()
    : emergencyPriorityEnabled = true,
      aggressiveRetryCount = 5,
      aggressiveRetryDelays = const [
        Duration(milliseconds: 500),
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 5),
      ],
      bypassCompression = true,
      bypassSyncInterval = true;

  Duration retryDelayForAttempt(int attempt) {
    if (attempt <= 0 || aggressiveRetryDelays.isEmpty) return Duration.zero;
    final index = attempt - 1;
    if (index >= aggressiveRetryDelays.length) {
      return aggressiveRetryDelays.last;
    }
    return aggressiveRetryDelays[index];
  }
}
