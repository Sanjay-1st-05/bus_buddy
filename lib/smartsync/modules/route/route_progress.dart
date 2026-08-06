import 'package:esec_bus/smartsync/modules/route/route_progress_status.dart';
import 'package:esec_bus/smartsync/modules/route/route_stop.dart';

class RouteProgress {
  final RouteProgressStatus status;
  final int currentSegmentIndex;
  final RouteStop? nextStop;
  final double routeCompletedPercent;
  final double distanceRemainingMeters;
  final double distanceFromRouteMeters;
  final bool isRouteDeviation;
  final bool isGpsDriftSuspected;
  final String reason;

  const RouteProgress({
    required this.status,
    required this.currentSegmentIndex,
    required this.nextStop,
    required this.routeCompletedPercent,
    required this.distanceRemainingMeters,
    required this.distanceFromRouteMeters,
    required this.isRouteDeviation,
    required this.isGpsDriftSuspected,
    required this.reason,
  });
}
