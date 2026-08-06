import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_trigger_type.dart';

class EmergencyEvent {
  final String eventId;
  final String deviceId;
  final String transportId;
  final EmergencyTriggerType triggerType;
  final LocationSample? location;
  final DateTime triggeredAt;
  final Map<String, Object?> metadata;

  const EmergencyEvent({
    required this.eventId,
    required this.deviceId,
    required this.transportId,
    required this.triggerType,
    required this.triggeredAt,
    this.location,
    this.metadata = const {},
  });
}
