import 'package:esec_bus/smartsync/models/movement_state.dart';

class MovementAnalysis {
  final MovementState state;
  final bool shouldAcceptForSync;
  final bool isGpsDriftSuspected;
  final double distanceMeters;
  final double? speedDeltaMetersPerSecond;
  final double? headingDeltaDegrees;
  final String reason;

  const MovementAnalysis({
    required this.state,
    required this.shouldAcceptForSync,
    required this.isGpsDriftSuspected,
    required this.distanceMeters,
    required this.speedDeltaMetersPerSecond,
    required this.headingDeltaDegrees,
    required this.reason,
  });
}
