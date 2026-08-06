import 'dart:math' as math;

import 'package:esec_bus/smartsync/models/location_sample.dart';

class GeoDistance {
  static const double _earthRadiusMeters = 6371000;

  const GeoDistance._();

  static double metersBetween(LocationSample from, LocationSample to) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final deltaLat = _toRadians(to.latitude - from.latitude);
    final deltaLon = _toRadians(to.longitude - from.longitude);

    final haversine =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final centralAngle =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));

    return _earthRadiusMeters * centralAngle;
  }

  static double headingDelta(double fromDegrees, double toDegrees) {
    final difference = (toDegrees - fromDegrees).abs() % 360;
    return difference > 180 ? 360 - difference : difference;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}
