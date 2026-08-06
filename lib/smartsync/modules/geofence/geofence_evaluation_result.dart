import 'package:esec_bus/smartsync/modules/geofence/geofence_event.dart';

class GeofenceEvaluationResult {
  final List<GeofenceEvent> events;
  final DateTime evaluatedAt;

  const GeofenceEvaluationResult({
    required this.events,
    required this.evaluatedAt,
  });

  bool get hasEvents => events.isNotEmpty;
}
