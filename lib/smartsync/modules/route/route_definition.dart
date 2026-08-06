import 'package:esec_bus/smartsync/modules/route/route_stop.dart';

class RouteDefinition {
  final String routeId;
  final String routeName;
  final List<RouteStop> stops;

  const RouteDefinition({
    required this.routeId,
    required this.routeName,
    required this.stops,
  });

  List<RouteStop> get orderedStops {
    return [...stops]..sort((a, b) => a.sequence.compareTo(b.sequence));
  }
}
