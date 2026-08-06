import 'package:esec_bus/features/tracking/services/trip_start_validator.dart';
import 'package:esec_bus/shared/models/bus_record.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:test/test.dart';

void main() {
  const driverId = 'DRV_BUS_01';
  final validator = TripStartValidator(startRadiusMeters: 100);

  BusRecord busWithPoints(List<Map<String, Object?>> points) {
    return BusRecord(
      id: 'BUS_01',
      data: {
        'assignment': {'driverId': driverId},
        'route': {'trackPoints': points},
      },
    );
  }

  LocationSample location(double latitude, double longitude) {
    return LocationSample(
      latitude: latitude,
      longitude: longitude,
      capturedAt: DateTime.utc(2026, 7, 20),
    );
  }

  test('allows trip within configured radius of first sequenced stop', () {
    final result = validator.validate(
      bus: busWithPoints([
        {
          'name': 'Second',
          'sequence': 2,
          'latitude': 11.01,
          'longitude': 77.01,
        },
        {
          'name': 'Starting Point',
          'sequence': 1,
          'latitude': 11.0,
          'longitude': 77.0,
        },
      ]),
      driverId: driverId,
      currentLocation: location(11.0005, 77.0),
    );

    expect(result.status, TripStartValidationStatus.eligible);
    expect(result.startStopName, 'Starting Point');
    expect(result.distanceToStartMeters, lessThan(100));
  });

  test('allows trip outside configured radius and reports distance', () {
    final result = validator.validate(
      bus: busWithPoints([
        {
          'name': 'Starting Point',
          'sequence': 0,
          'latitude': 11.0,
          'longitude': 77.0,
        },
      ]),
      driverId: driverId,
      currentLocation: location(11.002, 77.0),
    );

    expect(result.status, TripStartValidationStatus.outsideStartRadius);
    expect(result.canStart, isTrue);
    expect(result.distanceToStartMeters, greaterThan(100));
  });

  test(
    'allows trip when the actual first sequenced stop has no coordinates',
    () {
      final result = validator.validate(
        bus: busWithPoints([
          {
            'name': 'Later Stop',
            'sequence': 2,
            'latitude': 11.0,
            'longitude': 77.0,
          },
          {'name': 'First Stop', 'sequence': 1},
        ]),
        driverId: driverId,
        currentLocation: location(11.0, 77.0),
      );

      expect(result.status, TripStartValidationStatus.missingStartPoint);
      expect(result.canStart, isTrue);
    },
  );

  test('blocks a driver who is not assigned to the bus', () {
    final result = validator.validate(
      bus: busWithPoints([
        {
          'name': 'Starting Point',
          'sequence': 0,
          'latitude': 11.0,
          'longitude': 77.0,
        },
      ]),
      driverId: 'DRV_BUS_02',
      currentLocation: location(11.0, 77.0),
    );

    expect(result.status, TripStartValidationStatus.assignmentMismatch);
  });

  test('rejects an invalid current GPS coordinate', () {
    final result = validator.validate(
      bus: busWithPoints([
        {
          'name': 'Starting Point',
          'sequence': 0,
          'latitude': 11.0,
          'longitude': 77.0,
        },
      ]),
      driverId: driverId,
      currentLocation: location(0, 0),
    );

    expect(result.status, TripStartValidationStatus.invalidCurrentLocation);
  });
}
