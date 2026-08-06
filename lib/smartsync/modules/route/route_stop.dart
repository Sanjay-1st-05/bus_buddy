import 'package:esec_bus/smartsync/models/location_sample.dart';

class RouteStop {
  final String stopId;
  final String name;
  final LocationSample location;
  final int sequence;

  const RouteStop({
    required this.stopId,
    required this.name,
    required this.location,
    required this.sequence,
  });
}
