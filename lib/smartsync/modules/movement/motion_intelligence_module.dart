import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/models/movement_state.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';
import 'package:esec_bus/smartsync/modules/movement/movement_analysis.dart';
import 'package:esec_bus/smartsync/modules/movement/movement_rules.dart';

class MotionIntelligenceModule implements SmartSyncMovementAnalyzer {
  final MovementRules rules;

  const MotionIntelligenceModule({this.rules = const MovementRules.defaults()});

  factory MotionIntelligenceModule.fromConfig(SmartSyncConfig config) {
    return MotionIntelligenceModule(
      rules: MovementRules(
        movementThresholdMeters: config.movementThresholdMeters,
        stationarySpeedMetersPerSecond:
            const MovementRules.defaults().stationarySpeedMetersPerSecond,
        movingSpeedMetersPerSecond:
            const MovementRules.defaults().movingSpeedMetersPerSecond,
        accelerationDeltaMetersPerSecond:
            const MovementRules.defaults().accelerationDeltaMetersPerSecond,
        turningHeadingDeltaDegrees:
            const MovementRules.defaults().turningHeadingDeltaDegrees,
        maxGpsAccuracyMeters:
            const MovementRules.defaults().maxGpsAccuracyMeters,
        impossibleJumpSpeedMetersPerSecond:
            const MovementRules.defaults().impossibleJumpSpeedMetersPerSecond,
        idleDuration: const MovementRules.defaults().idleDuration,
      ),
    );
  }

  @override
  MovementState analyze(LocationSample previous, LocationSample current) {
    return analyzeMovement(previous: previous, current: current).state;
  }

  MovementAnalysis analyzeMovement({
    required LocationSample previous,
    required LocationSample current,
    LocationSample? lastAcceptedSample,
  }) {
    if (!previous.hasValidCoordinates || !current.hasValidCoordinates) {
      return _analysis(
        type: MovementType.stopped,
        current: current,
        distanceMeters: 0,
        shouldAcceptForSync: false,
        isGpsDriftSuspected: false,
        reason: 'invalid_coordinates',
      );
    }

    if (_hasPoorAccuracy(current)) {
      return _analysis(
        type: MovementType.stopped,
        current: current,
        distanceMeters: 0,
        shouldAcceptForSync: false,
        isGpsDriftSuspected: true,
        reason: 'poor_gps_accuracy',
      );
    }

    final reference = lastAcceptedSample ?? previous;
    final distanceFromLastAccepted = GeoDistance.metersBetween(
      reference,
      current,
    );
    final distanceFromPrevious = GeoDistance.metersBetween(previous, current);
    final elapsed = current.capturedAt.difference(previous.capturedAt);
    final calculatedSpeed = _calculatedSpeed(distanceFromPrevious, elapsed);
    final speed = current.speedMetersPerSecond ?? calculatedSpeed ?? 0;
    final speedDelta = _speedDelta(previous, current);
    final headingDelta = _headingDelta(previous, current);

    if (_isImpossibleJump(distanceFromPrevious, elapsed)) {
      return _analysis(
        type: MovementType.stopped,
        current: current,
        distanceMeters: distanceFromLastAccepted,
        speedDeltaMetersPerSecond: speedDelta,
        headingDeltaDegrees: headingDelta,
        shouldAcceptForSync: false,
        isGpsDriftSuspected: true,
        reason: 'impossible_jump',
      );
    }

    final movementType = _classify(
      speed: speed,
      distanceMeters: distanceFromPrevious,
      elapsed: elapsed,
      speedDeltaMetersPerSecond: speedDelta,
      headingDeltaDegrees: headingDelta,
    );

    final passesThreshold =
        distanceFromLastAccepted >= rules.movementThresholdMeters;
    final shouldAccept =
        passesThreshold &&
        movementType != MovementType.stopped &&
        movementType != MovementType.parked;

    return _analysis(
      type: movementType,
      current: current,
      distanceMeters: distanceFromLastAccepted,
      speedDeltaMetersPerSecond: speedDelta,
      headingDeltaDegrees: headingDelta,
      shouldAcceptForSync: shouldAccept,
      isGpsDriftSuspected: false,
      reason: shouldAccept
          ? 'movement_threshold_passed'
          : _reasonForSkippedMovement(movementType, passesThreshold),
    );
  }

  bool _hasPoorAccuracy(LocationSample sample) {
    final accuracy = sample.accuracyMeters;
    return accuracy != null && accuracy > rules.maxGpsAccuracyMeters;
  }

  bool _isImpossibleJump(double distanceMeters, Duration elapsed) {
    final speed = _calculatedSpeed(distanceMeters, elapsed);
    return speed != null && speed > rules.impossibleJumpSpeedMetersPerSecond;
  }

  MovementType _classify({
    required double speed,
    required double distanceMeters,
    required Duration elapsed,
    required double? speedDeltaMetersPerSecond,
    required double? headingDeltaDegrees,
  }) {
    if (distanceMeters < 1 && elapsed >= rules.idleDuration) {
      return MovementType.parked;
    }
    if (speed <= rules.stationarySpeedMetersPerSecond && distanceMeters < 3) {
      return MovementType.stopped;
    }
    if (speed <= rules.stationarySpeedMetersPerSecond) {
      return MovementType.idle;
    }
    if ((speedDeltaMetersPerSecond ?? 0) >=
        rules.accelerationDeltaMetersPerSecond) {
      return MovementType.accelerating;
    }
    if ((headingDeltaDegrees ?? 0) >= rules.turningHeadingDeltaDegrees) {
      return MovementType.turning;
    }
    if (speed >= rules.movingSpeedMetersPerSecond ||
        distanceMeters >= rules.movementThresholdMeters) {
      return MovementType.moving;
    }

    return MovementType.idle;
  }

  double? _calculatedSpeed(double distanceMeters, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0) return null;
    return distanceMeters / (elapsed.inMilliseconds / 1000);
  }

  double? _speedDelta(LocationSample previous, LocationSample current) {
    final previousSpeed = previous.speedMetersPerSecond;
    final currentSpeed = current.speedMetersPerSecond;
    if (previousSpeed == null || currentSpeed == null) return null;
    return currentSpeed - previousSpeed;
  }

  double? _headingDelta(LocationSample previous, LocationSample current) {
    final previousHeading = previous.headingDegrees;
    final currentHeading = current.headingDegrees;
    if (previousHeading == null || currentHeading == null) return null;
    return GeoDistance.headingDelta(previousHeading, currentHeading);
  }

  String _reasonForSkippedMovement(
    MovementType movementType,
    bool passesThreshold,
  ) {
    if (!passesThreshold) return 'movement_below_threshold';
    if (movementType == MovementType.parked) return 'vehicle_parked';
    if (movementType == MovementType.stopped) return 'vehicle_stopped';
    return 'movement_not_syncable';
  }

  MovementAnalysis _analysis({
    required MovementType type,
    required LocationSample current,
    required double distanceMeters,
    required bool shouldAcceptForSync,
    required bool isGpsDriftSuspected,
    required String reason,
    double? speedDeltaMetersPerSecond,
    double? headingDeltaDegrees,
  }) {
    return MovementAnalysis(
      state: MovementState(
        type: type,
        distanceSinceLastSyncMeters: distanceMeters,
        lastAcceptedSample: shouldAcceptForSync ? current : null,
      ),
      shouldAcceptForSync: shouldAcceptForSync,
      isGpsDriftSuspected: isGpsDriftSuspected,
      distanceMeters: distanceMeters,
      speedDeltaMetersPerSecond: speedDeltaMetersPerSecond,
      headingDeltaDegrees: headingDeltaDegrees,
      reason: reason,
    );
  }
}
