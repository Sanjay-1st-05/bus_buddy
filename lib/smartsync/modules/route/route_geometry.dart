import 'dart:math' as math;

import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';

class RouteGeometry {
  static const double _metersPerDegreeLatitude = 111320;

  const RouteGeometry._();

  static double routeLengthMeters(List<LocationSample> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      total += GeoDistance.metersBetween(points[index], points[index + 1]);
    }
    return total;
  }

  static RouteProjection projectOntoRoute({
    required LocationSample point,
    required List<LocationSample> routePoints,
  }) {
    if (routePoints.length < 2) {
      return const RouteProjection.empty();
    }

    var bestDistance = double.infinity;
    var bestSegment = 0;
    var bestDistanceAlongRoute = 0.0;
    var distanceBeforeSegment = 0.0;

    for (var index = 0; index < routePoints.length - 1; index++) {
      final start = routePoints[index];
      final end = routePoints[index + 1];
      final segmentLength = GeoDistance.metersBetween(start, end);
      final projection = _projectToSegment(point, start, end);

      if (projection.distanceMeters < bestDistance) {
        bestDistance = projection.distanceMeters;
        bestSegment = index;
        bestDistanceAlongRoute =
            distanceBeforeSegment + (segmentLength * projection.fraction);
      }

      distanceBeforeSegment += segmentLength;
    }

    return RouteProjection(
      distanceFromRouteMeters: bestDistance,
      segmentIndex: bestSegment,
      distanceAlongRouteMeters: bestDistanceAlongRoute,
    );
  }

  static _SegmentProjection _projectToSegment(
    LocationSample point,
    LocationSample start,
    LocationSample end,
  ) {
    final origin = _toLocalMeters(start, start);
    final target = _toLocalMeters(end, start);
    final current = _toLocalMeters(point, start);

    final dx = target.x - origin.x;
    final dy = target.y - origin.y;
    final lengthSquared = (dx * dx) + (dy * dy);
    final rawFraction = lengthSquared == 0
        ? 0.0
        : (((current.x - origin.x) * dx) + ((current.y - origin.y) * dy)) /
              lengthSquared;
    final fraction = rawFraction.clamp(0, 1).toDouble();
    final closestX = origin.x + (fraction * dx);
    final closestY = origin.y + (fraction * dy);
    final distance = math.sqrt(
      math.pow(current.x - closestX, 2) + math.pow(current.y - closestY, 2),
    );

    return _SegmentProjection(distanceMeters: distance, fraction: fraction);
  }

  static _LocalPoint _toLocalMeters(
    LocationSample point,
    LocationSample origin,
  ) {
    final avgLatitude =
        ((point.latitude + origin.latitude) / 2) * math.pi / 180;
    final metersPerDegreeLongitude =
        _metersPerDegreeLatitude * math.cos(avgLatitude);

    return _LocalPoint(
      x: (point.longitude - origin.longitude) * metersPerDegreeLongitude,
      y: (point.latitude - origin.latitude) * _metersPerDegreeLatitude,
    );
  }
}

class RouteProjection {
  final double distanceFromRouteMeters;
  final int segmentIndex;
  final double distanceAlongRouteMeters;

  const RouteProjection({
    required this.distanceFromRouteMeters,
    required this.segmentIndex,
    required this.distanceAlongRouteMeters,
  });

  const RouteProjection.empty()
    : distanceFromRouteMeters = double.infinity,
      segmentIndex = -1,
      distanceAlongRouteMeters = 0;
}

class _SegmentProjection {
  final double distanceMeters;
  final double fraction;

  const _SegmentProjection({
    required this.distanceMeters,
    required this.fraction,
  });
}

class _LocalPoint {
  final double x;
  final double y;

  const _LocalPoint({required this.x, required this.y});
}
