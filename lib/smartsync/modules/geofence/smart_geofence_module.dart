import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_definition.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_evaluation_result.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_event.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_event_type.dart';
import 'package:esec_bus/smartsync/modules/geofence/geofence_type.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';

class SmartGeofenceModule implements SmartSyncGeofenceEvaluator {
  final double defaultRadiusMeters;
  final double defaultApproachRadiusMultiplier;

  const SmartGeofenceModule({
    this.defaultRadiusMeters = 100,
    this.defaultApproachRadiusMultiplier = 2,
  });

  factory SmartGeofenceModule.fromConfig(SmartSyncConfig config) {
    return SmartGeofenceModule(
      defaultRadiusMeters: config.geofenceRadiusMeters,
    );
  }

  @override
  GeofenceEvaluationResult evaluate({
    required List<GeofenceDefinition> geofences,
    required LocationSample currentLocation,
    LocationSample? previousLocation,
  }) {
    if (!currentLocation.hasValidCoordinates) {
      return GeofenceEvaluationResult(
        events: const [],
        evaluatedAt: currentLocation.capturedAt,
      );
    }

    final events = <GeofenceEvent>[];
    for (final geofence in geofences) {
      if (!geofence.center.hasValidCoordinates) continue;

      final currentDistance = GeoDistance.metersBetween(
        currentLocation,
        geofence.center,
      );
      final previousDistance =
          previousLocation == null || !previousLocation.hasValidCoordinates
          ? null
          : GeoDistance.metersBetween(previousLocation, geofence.center);

      final radius = _radiusFor(geofence);
      final approachRadius =
          geofence.approachRadiusMeters ??
          (radius * defaultApproachRadiusMultiplier);
      final wasInside = previousDistance != null && previousDistance <= radius;
      final isInside = currentDistance <= radius;

      if (!wasInside && isInside) {
        events.add(
          _eventFor(
            geofence,
            currentDistance,
            currentLocation.capturedAt,
            true,
          ),
        );
        continue;
      }

      if (wasInside && !isInside) {
        events.add(
          GeofenceEvent(
            geofence: geofence,
            eventType: _departureTypeFor(geofence.type),
            distanceMeters: currentDistance,
            occurredAt: currentLocation.capturedAt,
            reason: _departureReasonFor(geofence.type),
          ),
        );
        continue;
      }

      final wasApproaching =
          previousDistance != null &&
          previousDistance <= approachRadius &&
          previousDistance > radius;
      final isApproaching =
          currentDistance <= approachRadius && currentDistance > radius;
      final movedCloser =
          previousDistance == null || currentDistance < previousDistance;

      if (!isInside && isApproaching && !wasApproaching && movedCloser) {
        events.add(
          GeofenceEvent(
            geofence: geofence,
            eventType: GeofenceEventType.approaching,
            distanceMeters: currentDistance,
            occurredAt: currentLocation.capturedAt,
            reason: _approachReasonFor(geofence.type),
          ),
        );
      }
    }

    return GeofenceEvaluationResult(
      events: events,
      evaluatedAt: currentLocation.capturedAt,
    );
  }

  double _radiusFor(GeofenceDefinition geofence) {
    return geofence.radiusMeters > 0
        ? geofence.radiusMeters
        : defaultRadiusMeters;
  }

  GeofenceEvent _eventFor(
    GeofenceDefinition geofence,
    double distanceMeters,
    DateTime occurredAt,
    bool entered,
  ) {
    return GeofenceEvent(
      geofence: geofence,
      eventType: _entryTypeFor(geofence.type, entered),
      distanceMeters: distanceMeters,
      occurredAt: occurredAt,
      reason: _entryReasonFor(geofence.type),
    );
  }

  GeofenceEventType _entryTypeFor(GeofenceType type, bool entered) {
    if (type == GeofenceType.busStop) return GeofenceEventType.arrived;
    return GeofenceEventType.entered;
  }

  GeofenceEventType _departureTypeFor(GeofenceType type) {
    if (type == GeofenceType.busStop) return GeofenceEventType.departed;
    return GeofenceEventType.exited;
  }

  String _entryReasonFor(GeofenceType type) {
    return switch (type) {
      GeofenceType.campus => 'campus_entered',
      GeofenceType.busStop => 'bus_stop_arrived',
      GeofenceType.depot => 'depot_entered',
      GeofenceType.custom => 'geofence_entered',
    };
  }

  String _departureReasonFor(GeofenceType type) {
    return switch (type) {
      GeofenceType.campus => 'campus_exited',
      GeofenceType.busStop => 'bus_stop_departed',
      GeofenceType.depot => 'depot_exited',
      GeofenceType.custom => 'geofence_exited',
    };
  }

  String _approachReasonFor(GeofenceType type) {
    return switch (type) {
      GeofenceType.campus => 'approaching_campus',
      GeofenceType.busStop => 'approaching_bus_stop',
      GeofenceType.depot => 'approaching_depot',
      GeofenceType.custom => 'approaching_geofence',
    };
  }
}
