import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';
import 'package:esec_bus/smartsync/modules/route/route_awareness_rules.dart';
import 'package:esec_bus/smartsync/modules/route/route_definition.dart';
import 'package:esec_bus/smartsync/modules/route/route_geometry.dart';
import 'package:esec_bus/smartsync/modules/route/route_progress.dart';
import 'package:esec_bus/smartsync/modules/route/route_progress_status.dart';
import 'package:esec_bus/smartsync/modules/route/route_stop.dart';

class RouteAwarenessModule implements SmartSyncRouteAnalyzer {
  final RouteAwarenessRules rules;

  const RouteAwarenessModule({
    this.rules = const RouteAwarenessRules.defaults(),
  });

  @override
  RouteProgress analyze({
    required RouteDefinition route,
    required LocationSample currentLocation,
    LocationSample? previousLocation,
  }) {
    final stops = route.orderedStops;
    if (stops.length < 2 || !currentLocation.hasValidCoordinates) {
      return _progress(
        status: RouteProgressStatus.unavailable,
        reason: 'route_unavailable',
      );
    }

    final points = stops.map((stop) => stop.location).toList(growable: false);
    final totalLength = RouteGeometry.routeLengthMeters(points);
    if (totalLength <= 0) {
      return _progress(
        status: RouteProgressStatus.unavailable,
        reason: 'route_length_unavailable',
      );
    }

    if (_isUnrealisticJump(previousLocation, currentLocation)) {
      return _progress(
        status: RouteProgressStatus.driftSuspected,
        distanceFromRouteMeters: double.infinity,
        isGpsDriftSuspected: true,
        reason: 'unrealistic_location_jump',
      );
    }

    final projection = RouteGeometry.projectOntoRoute(
      point: currentLocation,
      routePoints: points,
    );
    final distanceRemaining =
        (totalLength - projection.distanceAlongRouteMeters).clamp(
          0,
          totalLength,
        );
    final completedPercent = totalLength == 0
        ? 0.0
        : ((projection.distanceAlongRouteMeters / totalLength) * 100)
              .clamp(0, 100)
              .toDouble();
    final nextStop = _nextStop(stops, projection.segmentIndex, currentLocation);
    final status = _statusFor(
      projection: projection,
      distanceRemaining: distanceRemaining.toDouble(),
      nextStop: nextStop,
      currentLocation: currentLocation,
    );

    return RouteProgress(
      status: status,
      currentSegmentIndex: projection.segmentIndex,
      nextStop: nextStop,
      routeCompletedPercent: completedPercent,
      distanceRemainingMeters: distanceRemaining.toDouble(),
      distanceFromRouteMeters: projection.distanceFromRouteMeters,
      isRouteDeviation: status == RouteProgressStatus.deviated,
      isGpsDriftSuspected: status == RouteProgressStatus.driftSuspected,
      reason: _reasonFor(status),
    );
  }

  bool _isUnrealisticJump(
    LocationSample? previousLocation,
    LocationSample currentLocation,
  ) {
    if (previousLocation == null || !previousLocation.hasValidCoordinates) {
      return false;
    }

    return GeoDistance.metersBetween(previousLocation, currentLocation) >=
        rules.unrealisticJumpMeters;
  }

  RouteStop? _nextStop(
    List<RouteStop> stops,
    int segmentIndex,
    LocationSample currentLocation,
  ) {
    final nextIndex = (segmentIndex + 1).clamp(0, stops.length - 1);
    final lastStop = stops.last;
    if (GeoDistance.metersBetween(currentLocation, lastStop.location) <=
        rules.completionRadiusMeters) {
      return null;
    }
    return stops[nextIndex];
  }

  RouteProgressStatus _statusFor({
    required RouteProjection projection,
    required double distanceRemaining,
    required RouteStop? nextStop,
    required LocationSample currentLocation,
  }) {
    if (distanceRemaining <= rules.completionRadiusMeters) {
      return RouteProgressStatus.completed;
    }
    if (projection.distanceFromRouteMeters >= rules.driftDistanceMeters) {
      return RouteProgressStatus.driftSuspected;
    }
    if (projection.distanceFromRouteMeters > rules.maxOnRouteDistanceMeters) {
      return RouteProgressStatus.deviated;
    }
    if (nextStop != null &&
        GeoDistance.metersBetween(currentLocation, nextStop.location) <=
            rules.stopArrivalRadiusMeters) {
      return RouteProgressStatus.approachingStop;
    }
    return RouteProgressStatus.onRoute;
  }

  String _reasonFor(RouteProgressStatus status) {
    return switch (status) {
      RouteProgressStatus.unavailable => 'route_unavailable',
      RouteProgressStatus.onRoute => 'vehicle_on_route',
      RouteProgressStatus.approachingStop => 'approaching_next_stop',
      RouteProgressStatus.deviated => 'route_deviation_detected',
      RouteProgressStatus.driftSuspected => 'gps_drift_suspected',
      RouteProgressStatus.completed => 'route_completed',
    };
  }

  RouteProgress _progress({
    required RouteProgressStatus status,
    required String reason,
    double distanceFromRouteMeters = 0,
    bool isGpsDriftSuspected = false,
  }) {
    return RouteProgress(
      status: status,
      currentSegmentIndex: -1,
      nextStop: null,
      routeCompletedPercent: 0,
      distanceRemainingMeters: 0,
      distanceFromRouteMeters: distanceFromRouteMeters,
      isRouteDeviation: false,
      isGpsDriftSuspected: isGpsDriftSuspected,
      reason: reason,
    );
  }
}
