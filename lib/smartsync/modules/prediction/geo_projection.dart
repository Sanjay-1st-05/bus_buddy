import 'dart:math' as math;

import 'package:esec_bus/smartsync/models/location_sample.dart';

class GeoProjection {
  static const double _earthRadiusMeters = 6371000;

  const GeoProjection._();

  static LocationSample project({
    required LocationSample from,
    required double distanceMeters,
    required double headingDegrees,
    required DateTime capturedAt,
  }) {
    final angularDistance = distanceMeters / _earthRadiusMeters;
    final bearing = _toRadians(headingDegrees);
    final startLat = _toRadians(from.latitude);
    final startLng = _toRadians(from.longitude);

    final projectedLat = math.asin(
      math.sin(startLat) * math.cos(angularDistance) +
          math.cos(startLat) * math.sin(angularDistance) * math.cos(bearing),
    );
    final projectedLng =
        startLng +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(startLat),
          math.cos(angularDistance) -
              math.sin(startLat) * math.sin(projectedLat),
        );

    return LocationSample(
      latitude: _toDegrees(projectedLat),
      longitude: _normalizeLongitude(_toDegrees(projectedLng)),
      capturedAt: capturedAt,
      speedMetersPerSecond: from.speedMetersPerSecond,
      headingDegrees: headingDegrees,
      accuracyMeters: from.accuracyMeters,
    );
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _toDegrees(double radians) => radians * 180 / math.pi;

  static double _normalizeLongitude(double longitude) {
    return ((longitude + 540) % 360) - 180;
  }
}
