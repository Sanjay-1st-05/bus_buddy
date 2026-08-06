import 'dart:math' as math;

import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';
import 'package:esec_bus/smartsync/modules/prediction/geo_projection.dart';
import 'package:esec_bus/smartsync/modules/prediction/prediction_input.dart';
import 'package:esec_bus/smartsync/modules/prediction/prediction_result.dart';
import 'package:esec_bus/smartsync/modules/prediction/prediction_rules.dart';

class PredictiveTrackingModule implements SmartSyncPredictionEngine {
  final PredictionRules rules;

  const PredictiveTrackingModule({
    this.rules = const PredictionRules.defaults(),
  });

  factory PredictiveTrackingModule.fromConfig(SmartSyncConfig config) {
    return PredictiveTrackingModule(
      rules: PredictionRules(
        predictionWindow: config.predictionWindow,
        minimumSpeedMetersPerSecond:
            const PredictionRules.defaults().minimumSpeedMetersPerSecond,
        confidenceDecayPerSecond:
            const PredictionRules.defaults().confidenceDecayPerSecond,
        roadDirectionConfidenceBonus:
            const PredictionRules.defaults().roadDirectionConfidenceBonus,
        historicalMovementConfidenceBonus:
            const PredictionRules.defaults().historicalMovementConfidenceBonus,
        minimumConfidence: const PredictionRules.defaults().minimumConfidence,
      ),
    );
  }

  @override
  PredictionResult predict(PredictionInput input) {
    if (input.hasLiveGps) {
      return const PredictionResult.inactive();
    }

    if (!input.previousGps.hasValidCoordinates) {
      return const PredictionResult.inactive(reason: 'invalid_previous_gps');
    }

    final elapsed = input.predictionTime.difference(
      input.previousGps.capturedAt,
    );
    if (elapsed.isNegative || elapsed == Duration.zero) {
      return const PredictionResult.inactive(reason: 'prediction_not_due');
    }
    if (elapsed > rules.predictionWindow) {
      return const PredictionResult.inactive(
        reason: 'prediction_window_expired',
      );
    }

    final speed = _resolveSpeed(input);
    final heading = _resolveHeading(input);

    if (speed < rules.minimumSpeedMetersPerSecond) {
      return const PredictionResult.inactive(reason: 'speed_too_low');
    }
    if (heading == null) {
      return const PredictionResult.inactive(reason: 'heading_unavailable');
    }

    final projectedDistance = speed * (elapsed.inMilliseconds / 1000);
    final predictedPosition = GeoProjection.project(
      from: input.previousGps,
      distanceMeters: projectedDistance,
      headingDegrees: heading,
      capturedAt: input.predictionTime,
    );

    return PredictionResult(
      isActive: true,
      predictedPosition: predictedPosition,
      estimatedEta: _estimatedEta(input.distanceToDestinationMeters, speed),
      confidenceScore: _confidence(input, elapsed),
      reason: 'prediction_active',
    );
  }

  double _resolveSpeed(PredictionInput input) {
    final directSpeed = input.previousGps.speedMetersPerSecond;
    if (directSpeed != null) return directSpeed;

    if (input.historicalMovement.length < 2) return 0;
    final previous =
        input.historicalMovement[input.historicalMovement.length - 2];
    final current = input.historicalMovement.last;
    final elapsed = current.capturedAt.difference(previous.capturedAt);
    if (elapsed.inMilliseconds <= 0) return 0;

    final distance = GeoDistance.metersBetween(previous, current);
    return distance / (elapsed.inMilliseconds / 1000);
  }

  double? _resolveHeading(PredictionInput input) {
    if (input.roadHeadingDegrees != null) return input.roadHeadingDegrees;
    if (input.previousGps.headingDegrees != null) {
      return input.previousGps.headingDegrees;
    }

    if (input.historicalMovement.length < 2) return null;
    final previous =
        input.historicalMovement[input.historicalMovement.length - 2];
    final current = input.historicalMovement.last;
    return _bearing(previous, current);
  }

  Duration? _estimatedEta(double? distanceToDestinationMeters, double speed) {
    if (distanceToDestinationMeters == null || speed <= 0) return null;
    return Duration(
      milliseconds: ((distanceToDestinationMeters / speed) * 1000).round(),
    );
  }

  double _confidence(PredictionInput input, Duration elapsed) {
    var confidence = 1 - (elapsed.inSeconds * rules.confidenceDecayPerSecond);
    if (input.roadHeadingDegrees != null) {
      confidence += rules.roadDirectionConfidenceBonus;
    }
    if (input.historicalMovement.length >= 2) {
      confidence += rules.historicalMovementConfidenceBonus;
    }

    return confidence.clamp(rules.minimumConfidence, 1).toDouble();
  }

  double _bearing(LocationSample from, LocationSample to) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final deltaLng = _toRadians(to.longitude - from.longitude);
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return (_toDegrees(math.atan2(y, x)) + 360) % 360;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  double _toDegrees(double radians) => radians * 180 / math.pi;
}
