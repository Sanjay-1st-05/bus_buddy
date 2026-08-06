import 'package:esec_bus/smartsync/models/smartsync_enums.dart';

class SynchronizationPolicy {
  final Map<NetworkQuality, Duration> intervals;
  final Duration emergencyInterval;
  final Duration minimumInterval;

  const SynchronizationPolicy({
    required this.intervals,
    required this.emergencyInterval,
    required this.minimumInterval,
  });

  factory SynchronizationPolicy.fromIntervals(
    Map<NetworkQuality, Duration> intervals, {
    Duration emergencyInterval = Duration.zero,
    Duration minimumInterval = const Duration(seconds: 1),
  }) {
    return SynchronizationPolicy(
      intervals: Map.unmodifiable(intervals),
      emergencyInterval: emergencyInterval,
      minimumInterval: minimumInterval,
    );
  }

  Duration intervalFor(NetworkQuality quality) {
    final interval = intervals[quality] ?? Duration.zero;
    if (quality == NetworkQuality.offline || interval == Duration.zero) {
      return Duration.zero;
    }
    if (interval < minimumInterval) return minimumInterval;
    return interval;
  }
}
