import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('SmartGeofenceModule', () {
    const module = SmartGeofenceModule();
    final now = DateTime.utc(2026, 7, 12, 10);

    LocationSample point(double latitude, double longitude) {
      return LocationSample(
        latitude: latitude,
        longitude: longitude,
        capturedAt: now,
      );
    }

    GeofenceDefinition geofence({
      GeofenceType type = GeofenceType.busStop,
      double radius = 100,
      double? approachRadius,
    }) {
      return GeofenceDefinition(
        geofenceId: 'g1',
        name: 'Main Stop',
        type: type,
        center: point(11.0000, 77.0000),
        radiusMeters: radius,
        approachRadiusMeters: approachRadius,
      );
    }

    test('emits bus stop arrival when entering stop radius', () {
      final result = module.evaluate(
        geofences: [geofence()],
        previousLocation: point(10.9980, 77.0000),
        currentLocation: point(10.9995, 77.0000),
      );

      expect(result.hasEvents, isTrue);
      expect(result.events.single.eventType, GeofenceEventType.arrived);
      expect(result.events.single.reason, 'bus_stop_arrived');
    });

    test('emits bus stop departure when leaving stop radius', () {
      final result = module.evaluate(
        geofences: [geofence()],
        previousLocation: point(10.9995, 77.0000),
        currentLocation: point(10.9980, 77.0000),
      );

      expect(result.events.single.eventType, GeofenceEventType.departed);
      expect(result.events.single.reason, 'bus_stop_departed');
    });

    test('emits campus entry and exit events', () {
      final campus = geofence(type: GeofenceType.campus);
      final entry = module.evaluate(
        geofences: [campus],
        previousLocation: point(10.9980, 77.0000),
        currentLocation: point(10.9995, 77.0000),
      );
      final exit = module.evaluate(
        geofences: [campus],
        previousLocation: point(10.9995, 77.0000),
        currentLocation: point(10.9980, 77.0000),
      );

      expect(entry.events.single.eventType, GeofenceEventType.entered);
      expect(entry.events.single.reason, 'campus_entered');
      expect(exit.events.single.eventType, GeofenceEventType.exited);
      expect(exit.events.single.reason, 'campus_exited');
    });

    test('emits approaching event before stop arrival', () {
      final result = module.evaluate(
        geofences: [geofence(approachRadius: 250)],
        previousLocation: point(10.9970, 77.0000),
        currentLocation: point(10.9980, 77.0000),
      );

      expect(result.events.single.eventType, GeofenceEventType.approaching);
      expect(result.events.single.reason, 'approaching_bus_stop');
    });

    test(
      'does not emit duplicate approaching event while already approaching',
      () {
        final result = module.evaluate(
          geofences: [geofence(approachRadius: 250)],
          previousLocation: point(10.9980, 77.0000),
          currentLocation: point(10.9985, 77.0000),
        );

        expect(result.events, isEmpty);
      },
    );

    test('ignores invalid current locations', () {
      final result = module.evaluate(
        geofences: [geofence()],
        currentLocation: LocationSample(
          latitude: 0,
          longitude: 0,
          capturedAt: now,
        ),
      );

      expect(result.events, isEmpty);
    });

    test('evaluates multiple geofences in one pass', () {
      final result = module.evaluate(
        geofences: [
          geofence(type: GeofenceType.busStop),
          GeofenceDefinition(
            geofenceId: 'depot',
            name: 'Depot',
            type: GeofenceType.depot,
            center: point(11.0000, 77.0000),
            radiusMeters: 100,
          ),
        ],
        previousLocation: point(10.9980, 77.0000),
        currentLocation: point(10.9995, 77.0000),
      );

      expect(result.events, hasLength(2));
      expect(
        result.events.map((event) => event.reason),
        containsAll(['bus_stop_arrived', 'depot_entered']),
      );
    });

    test(
      'fromConfig uses configured default radius for invalid radius inputs',
      () {
        final configured = SmartGeofenceModule.fromConfig(
          SmartSyncConfig.defaults(),
        );
        final result = configured.evaluate(
          geofences: [geofence(radius: 0)],
          previousLocation: point(10.9980, 77.0000),
          currentLocation: point(10.9995, 77.0000),
        );

        expect(result.events.single.eventType, GeofenceEventType.arrived);
      },
    );

    test('ignores geofences with invalid centers', () {
      final result = module.evaluate(
        geofences: [
          GeofenceDefinition(
            geofenceId: 'invalid',
            name: 'Invalid',
            type: GeofenceType.custom,
            center: point(0, 0),
            radiusMeters: 100,
          ),
        ],
        previousLocation: point(10.9980, 77.0000),
        currentLocation: point(10.9995, 77.0000),
      );

      expect(result.events, isEmpty);
    });

    test('does not emit approaching event when moving away from geofence', () {
      final result = module.evaluate(
        geofences: [geofence(approachRadius: 250)],
        previousLocation: point(10.9980, 77.0000),
        currentLocation: point(10.9975, 77.0000),
      );

      expect(result.events, isEmpty);
    });
  });
}
