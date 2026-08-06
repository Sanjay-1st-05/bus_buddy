import 'dart:math' as math;

import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';

enum LiveEtaState { arrived, estimated, stopped }

class LiveTrackingMetrics {
  static const double arrivalRadiusMeters = 50;
  static const double minimumMovingSpeedMetersPerSecond = 0.8;
  static const double averageMovingSpeedMetersPerSecond = 8.33;
  static const double maximumReasonableSpeedMetersPerSecond = 33.33;

  final double distanceMeters;
  final int? etaMinutes;
  final LiveEtaState etaState;
  final double? effectiveSpeedMetersPerSecond;
  final bool usesEstimatedSpeed;

  const LiveTrackingMetrics({
    required this.distanceMeters,
    required this.etaState,
    this.etaMinutes,
    this.effectiveSpeedMetersPerSecond,
    this.usesEstimatedSpeed = false,
  });

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m away';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km away';
  }

  String get etaLabel {
    return switch (etaState) {
      LiveEtaState.arrived => 'Arrived',
      LiveEtaState.estimated => '$etaMinutes min',
      LiveEtaState.stopped => 'Stopped',
    };
  }

  static LiveTrackingMetrics calculate({
    required LocationSample busLocation,
    required LocationSample studentLocation,
    required bool isTripRunning,
  }) {
    final distanceMeters = GeoDistance.metersBetween(
      busLocation,
      studentLocation,
    );

    if (distanceMeters <= arrivalRadiusMeters) {
      return LiveTrackingMetrics(
        distanceMeters: distanceMeters,
        etaState: LiveEtaState.arrived,
        etaMinutes: 0,
      );
    }

    if (!isTripRunning) {
      return LiveTrackingMetrics(
        distanceMeters: distanceMeters,
        etaState: LiveEtaState.stopped,
      );
    }

    final reportedSpeed = busLocation.speedMetersPerSecond;
    final hasUsableReportedSpeed =
        reportedSpeed != null &&
        reportedSpeed.isFinite &&
        reportedSpeed >= minimumMovingSpeedMetersPerSecond;
    final effectiveSpeed = hasUsableReportedSpeed
        ? math.min(reportedSpeed, maximumReasonableSpeedMetersPerSecond)
        : averageMovingSpeedMetersPerSecond;

    final etaMinutes = math.max(
      1,
      (distanceMeters / effectiveSpeed / 60).ceil(),
    );
    return LiveTrackingMetrics(
      distanceMeters: distanceMeters,
      etaState: LiveEtaState.estimated,
      etaMinutes: etaMinutes,
      effectiveSpeedMetersPerSecond: effectiveSpeed,
      usesEstimatedSpeed: !hasUsableReportedSpeed,
    );
  }
}
