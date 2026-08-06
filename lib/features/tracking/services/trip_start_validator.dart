import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/shared/models/bus_record.dart';
import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/models/location_sample.dart';
import 'package:esec_bus/smartsync/modules/movement/geo_distance.dart';

enum TripStartValidationStatus {
  eligible,
  assignmentMismatch,
  missingStartPoint,
  invalidCurrentLocation,
  outsideStartRadius,
}

class TripStartValidationResult {
  final TripStartValidationStatus status;
  final String? startStopName;
  final double? distanceToStartMeters;
  final double startRadiusMeters;

  const TripStartValidationResult({
    required this.status,
    required this.startRadiusMeters,
    this.startStopName,
    this.distanceToStartMeters,
  });

  /// A first-stop location is advisory. A driver may start while travelling
  /// towards it, but an invalid assignment or GPS sample still blocks tracking.
  bool get canStart =>
      status != TripStartValidationStatus.assignmentMismatch &&
      status != TripStartValidationStatus.invalidCurrentLocation;
}

/// Builds a first-stop distance advisory without performing GPS or Firestore
/// work, which keeps the decision deterministic and independently testable.
class TripStartValidator {
  final double startRadiusMeters;

  TripStartValidator({double? startRadiusMeters})
    : startRadiusMeters =
          startRadiusMeters ?? SmartSyncConfig.defaults().geofenceRadiusMeters;

  TripStartValidationResult validate({
    required BusRecord bus,
    required String driverId,
    required LocationSample currentLocation,
  }) {
    if (bus.assignedDriverId != driverId) {
      return TripStartValidationResult(
        status: TripStartValidationStatus.assignmentMismatch,
        startRadiusMeters: startRadiusMeters,
      );
    }

    final firstStop = _firstStop(bus.route['trackPoints']);
    if (firstStop == null || !firstStop.location.hasValidCoordinates) {
      return TripStartValidationResult(
        status: TripStartValidationStatus.missingStartPoint,
        startRadiusMeters: startRadiusMeters,
        startStopName: firstStop?.name,
      );
    }

    if (!currentLocation.hasValidCoordinates) {
      return TripStartValidationResult(
        status: TripStartValidationStatus.invalidCurrentLocation,
        startRadiusMeters: startRadiusMeters,
        startStopName: firstStop.name,
      );
    }

    final distance = GeoDistance.metersBetween(
      currentLocation,
      firstStop.location,
    );
    return TripStartValidationResult(
      status: distance <= startRadiusMeters
          ? TripStartValidationStatus.eligible
          : TripStartValidationStatus.outsideStartRadius,
      startRadiusMeters: startRadiusMeters,
      startStopName: firstStop.name,
      distanceToStartMeters: distance,
    );
  }

  _TripStartPoint? _firstStop(Object? value) {
    if (value is! List || value.isEmpty) return null;

    final stops = <_SequencedStop>[];
    for (var index = 0; index < value.length; index++) {
      final data = firestoreMap(value[index]);
      if (data.isEmpty) continue;
      final rawSequence = data['sequence'];
      final sequence = rawSequence is num ? rawSequence.toInt() : index;
      stops.add(_SequencedStop(data: data, sequence: sequence, index: index));
    }
    if (stops.isEmpty) return null;

    stops.sort((a, b) {
      final sequenceOrder = a.sequence.compareTo(b.sequence);
      return sequenceOrder != 0 ? sequenceOrder : a.index.compareTo(b.index);
    });

    final data = stops.first.data;
    final latitude = firestoreDouble(data['latitude']);
    final longitude = firestoreDouble(data['longitude']);
    if (latitude == null || longitude == null) return null;

    return _TripStartPoint(
      name: firestoreString(data['name']) ?? 'First stop',
      location: LocationSample(
        latitude: latitude,
        longitude: longitude,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
  }
}

class _SequencedStop {
  final Map<String, dynamic> data;
  final int sequence;
  final int index;

  const _SequencedStop({
    required this.data,
    required this.sequence,
    required this.index,
  });
}

class _TripStartPoint {
  final String name;
  final LocationSample location;

  const _TripStartPoint({required this.name, required this.location});
}
