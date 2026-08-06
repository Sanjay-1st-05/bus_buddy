import 'location_sample.dart';
import 'smartsync_enums.dart';

class MovementState {
  final MovementType type;
  final double distanceSinceLastSyncMeters;
  final LocationSample? lastAcceptedSample;

  const MovementState({
    required this.type,
    required this.distanceSinceLastSyncMeters,
    this.lastAcceptedSample,
  });

  bool passesThreshold(double thresholdMeters) {
    return distanceSinceLastSyncMeters >= thresholdMeters;
  }
}
