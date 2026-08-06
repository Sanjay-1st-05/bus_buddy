import 'package:esec_bus/smartsync/modules/geofence/geofence_definition.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_event_type.dart';

class GeofenceEvent {
  final GeofenceDefinition geofence;
  final GeofenceEventType eventType;
  final double distanceMeters;
  final DateTime occurredAt;
  final String reason;

  const GeofenceEvent({
    required this.geofence,
    required this.eventType,
    required this.distanceMeters,
    required this.occurredAt,
    required this.reason,
  });
}
