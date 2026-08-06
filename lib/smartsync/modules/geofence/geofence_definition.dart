import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_type.dart';

class GeofenceDefinition {
  final String geofenceId;
  final String name;
  final GeofenceType type;
  final LocationSample center;
  final double radiusMeters;
  final double? approachRadiusMeters;
  final Map<String, Object?> metadata;

  const GeofenceDefinition({
    required this.geofenceId,
    required this.name,
    required this.type,
    required this.center,
    required this.radiusMeters,
    this.approachRadiusMeters,
    this.metadata = const {},
  });
}
