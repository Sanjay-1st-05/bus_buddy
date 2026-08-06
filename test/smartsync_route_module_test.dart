import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('RouteAwarenessModule', () {
    const module = RouteAwarenessModule();
    final now = DateTime.utc(2026, 7, 12, 10);

    LocationSample point(double latitude, double longitude) {
      return LocationSample(
        latitude: latitude,
        longitude: longitude,
        capturedAt: now,
      );
    }

    RouteDefinition route() {
      return RouteDefinition(
        routeId: 'route-1',
        routeName: 'College Route',
        stops: [
          RouteStop(
            stopId: 'college',
            name: 'College',
            location: point(11.0000, 77.0000),
            sequence: 0,
          ),
          RouteStop(
            stopId: 'stop-a',
            name: 'Stop A',
            location: point(11.0100, 77.0000),
            sequence: 1,
          ),
          RouteStop(
            stopId: 'stop-b',
            name: 'Stop B',
            location: point(11.0200, 77.0000),
            sequence: 2,
          ),
        ],
      );
    }

    test('reports unavailable when route has fewer than two stops', () {
      final progress = module.analyze(
        route: RouteDefinition(
          routeId: 'bad',
          routeName: 'Bad Route',
          stops: [
            RouteStop(
              stopId: 'only',
              name: 'Only Stop',
              location: point(11.0, 77.0),
              sequence: 0,
            ),
          ],
        ),
        currentLocation: point(11.0, 77.0),
      );

      expect(progress.status, RouteProgressStatus.unavailable);
      expect(progress.reason, 'route_unavailable');
    });

    test('detects on-route progress and next stop', () {
      final progress = module.analyze(
        route: route(),
        currentLocation: point(11.0050, 77.0000),
      );

      expect(progress.status, RouteProgressStatus.onRoute);
      expect(progress.currentSegmentIndex, 0);
      expect(progress.nextStop?.stopId, 'stop-a');
      expect(progress.routeCompletedPercent, closeTo(25, 2));
      expect(progress.distanceRemainingMeters, greaterThan(0));
      expect(progress.isRouteDeviation, isFalse);
    });

    test('detects approaching next stop', () {
      final progress = module.analyze(
        route: route(),
        currentLocation: point(11.0095, 77.0000),
      );

      expect(progress.status, RouteProgressStatus.approachingStop);
      expect(progress.nextStop?.stopId, 'stop-a');
      expect(progress.reason, 'approaching_next_stop');
    });

    test('detects route deviation when away from route corridor', () {
      final progress = module.analyze(
        route: route(),
        currentLocation: point(11.0050, 77.0015),
      );

      expect(progress.status, RouteProgressStatus.deviated);
      expect(progress.isRouteDeviation, isTrue);
      expect(progress.distanceFromRouteMeters, greaterThan(100));
    });

    test('classifies far route jumps as GPS drift', () {
      final progress = module.analyze(
        route: route(),
        currentLocation: point(11.0050, 77.0100),
      );

      expect(progress.status, RouteProgressStatus.driftSuspected);
      expect(progress.isGpsDriftSuspected, isTrue);
      expect(progress.reason, 'gps_drift_suspected');
    });

    test('detects unrealistic transition from previous location', () {
      final progress = module.analyze(
        route: route(),
        previousLocation: point(11.0050, 77.0000),
        currentLocation: point(11.0500, 77.0000),
      );

      expect(progress.status, RouteProgressStatus.driftSuspected);
      expect(progress.isGpsDriftSuspected, isTrue);
      expect(progress.reason, 'unrealistic_location_jump');
    });

    test('detects completed route near final stop', () {
      final progress = module.analyze(
        route: route(),
        currentLocation: point(11.0200, 77.0000),
      );

      expect(progress.status, RouteProgressStatus.completed);
      expect(progress.nextStop, isNull);
      expect(progress.routeCompletedPercent, closeTo(100, 1));
      expect(progress.reason, 'route_completed');
    });

    test(
      'reports unavailable for invalid current location even with valid route',
      () {
        final progress = module.analyze(
          route: route(),
          currentLocation: point(0, 0),
        );

        expect(progress.status, RouteProgressStatus.unavailable);
        expect(progress.reason, 'route_unavailable');
      },
    );

    test('orders stops by sequence before calculating progress', () {
      final unorderedRoute = RouteDefinition(
        routeId: 'unordered',
        routeName: 'Unordered Route',
        stops: [
          RouteStop(
            stopId: 'stop-b',
            name: 'Stop B',
            location: point(11.0200, 77.0000),
            sequence: 2,
          ),
          RouteStop(
            stopId: 'college',
            name: 'College',
            location: point(11.0000, 77.0000),
            sequence: 0,
          ),
          RouteStop(
            stopId: 'stop-a',
            name: 'Stop A',
            location: point(11.0100, 77.0000),
            sequence: 1,
          ),
        ],
      );

      final progress = module.analyze(
        route: unorderedRoute,
        currentLocation: point(11.0050, 77.0000),
      );

      expect(progress.status, RouteProgressStatus.onRoute);
      expect(progress.nextStop?.stopId, 'stop-a');
      expect(progress.currentSegmentIndex, 0);
    });
  });

  group('RouteGeometry', () {
    test('calculates route length and projection distance', () {
      final points = [
        LocationSample(
          latitude: 11.0000,
          longitude: 77.0000,
          capturedAt: DateTime.utc(2026, 7, 12),
        ),
        LocationSample(
          latitude: 11.0100,
          longitude: 77.0000,
          capturedAt: DateTime.utc(2026, 7, 12),
        ),
      ];

      final length = RouteGeometry.routeLengthMeters(points);
      final projection = RouteGeometry.projectOntoRoute(
        point: LocationSample(
          latitude: 11.0050,
          longitude: 77.0000,
          capturedAt: DateTime.utc(2026, 7, 12),
        ),
        routePoints: points,
      );

      expect(length, greaterThan(1000));
      expect(projection.distanceFromRouteMeters, lessThan(1));
      expect(projection.segmentIndex, 0);
    });
  });
}
