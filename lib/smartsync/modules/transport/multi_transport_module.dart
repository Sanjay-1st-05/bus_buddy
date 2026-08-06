import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/transport/transport_policy.dart';
import 'package:esec_bus/smartsync/modules/transport/transport_profile.dart';
import 'package:esec_bus/smartsync/modules/transport/transport_validation_result.dart';

class MultiTransportModule {
  final Map<TransportType, TransportProfile> _profiles;

  MultiTransportModule({Map<TransportType, TransportProfile>? profiles})
    : _profiles = Map.unmodifiable(profiles ?? defaultProfiles);

  static final Map<TransportType, TransportProfile> defaultProfiles =
      Map.unmodifiable({
        TransportType.collegeBus: TransportProfile(
          type: TransportType.collegeBus,
          name: 'College Bus',
          policy: _publicPassengerPolicy(
            movementThresholdMeters: 20,
            geofenceRadiusMeters: 100,
          ),
        ),
        TransportType.schoolBus: TransportProfile(
          type: TransportType.schoolBus,
          name: 'School Bus',
          policy: _publicPassengerPolicy(
            movementThresholdMeters: 15,
            geofenceRadiusMeters: 75,
          ),
        ),
        TransportType.employeeShuttle: TransportProfile(
          type: TransportType.employeeShuttle,
          name: 'Employee Shuttle',
          policy: _publicPassengerPolicy(
            movementThresholdMeters: 20,
            geofenceRadiusMeters: 100,
          ),
        ),
        TransportType.publicBus: TransportProfile(
          type: TransportType.publicBus,
          name: 'Public Bus',
          policy: _publicPassengerPolicy(
            movementThresholdMeters: 25,
            geofenceRadiusMeters: 125,
          ),
        ),
        TransportType.ambulance: TransportProfile(
          type: TransportType.ambulance,
          name: 'Ambulance',
          policy: const TransportPolicy(
            movementThresholdMeters: 5,
            geofenceRadiusMeters: 50,
            maxReliableSpeedMetersPerSecond: 45,
            staleLocationAfter: Duration(seconds: 10),
            emergencyPriorityEnabled: true,
            routeAwarenessRequired: false,
          ),
        ),
        TransportType.deliveryVehicle: TransportProfile(
          type: TransportType.deliveryVehicle,
          name: 'Delivery Vehicle',
          policy: const TransportPolicy(
            movementThresholdMeters: 15,
            geofenceRadiusMeters: 60,
            maxReliableSpeedMetersPerSecond: 35,
            staleLocationAfter: Duration(seconds: 30),
            emergencyPriorityEnabled: false,
            routeAwarenessRequired: true,
          ),
        ),
        TransportType.taxi: TransportProfile(
          type: TransportType.taxi,
          name: 'Taxi',
          policy: const TransportPolicy(
            movementThresholdMeters: 10,
            geofenceRadiusMeters: 50,
            maxReliableSpeedMetersPerSecond: 40,
            staleLocationAfter: Duration(seconds: 20),
            emergencyPriorityEnabled: true,
            routeAwarenessRequired: false,
          ),
        ),
        TransportType.logisticsFleet: TransportProfile(
          type: TransportType.logisticsFleet,
          name: 'Logistics Fleet',
          policy: const TransportPolicy(
            movementThresholdMeters: 30,
            geofenceRadiusMeters: 150,
            maxReliableSpeedMetersPerSecond: 35,
            staleLocationAfter: Duration(seconds: 45),
            emergencyPriorityEnabled: false,
            routeAwarenessRequired: true,
          ),
        ),
        TransportType.agriculturalVehicle: TransportProfile(
          type: TransportType.agriculturalVehicle,
          name: 'Agricultural Vehicle',
          policy: const TransportPolicy(
            movementThresholdMeters: 8,
            geofenceRadiusMeters: 40,
            maxReliableSpeedMetersPerSecond: 15,
            staleLocationAfter: Duration(seconds: 45),
            emergencyPriorityEnabled: false,
            routeAwarenessRequired: false,
          ),
        ),
        TransportType.autonomousVehicle: TransportProfile(
          type: TransportType.autonomousVehicle,
          name: 'Autonomous Vehicle',
          policy: const TransportPolicy(
            movementThresholdMeters: 5,
            geofenceRadiusMeters: 30,
            maxReliableSpeedMetersPerSecond: 45,
            staleLocationAfter: Duration(seconds: 10),
            emergencyPriorityEnabled: true,
            routeAwarenessRequired: true,
          ),
        ),
      });

  List<TransportProfile> get profiles =>
      _profiles.values.toList(growable: false);

  TransportProfile profileFor(TransportType type) {
    final profile = _profiles[type];
    if (profile == null) {
      throw ArgumentError.value(type, 'type', 'Unsupported transport type');
    }
    return profile;
  }

  TransportPolicy policyFor(TransportType type) => profileFor(type).policy;

  bool supports(TransportType type) => _profiles.containsKey(type);

  TransportValidationResult validatePacket({
    required SyncPacket packet,
    required TransportType type,
    DateTime? now,
  }) {
    final profile = profileFor(type);
    final warnings = <String>[];
    final sample = packet.sample;
    final timestamp = now ?? DateTime.now();

    if (!sample.hasValidCoordinates) {
      warnings.add('Location coordinates are invalid.');
    }

    final age = timestamp.difference(sample.capturedAt);
    if (age > profile.policy.staleLocationAfter) {
      warnings.add('Location sample is stale for ${profile.name}.');
    }

    final speed = sample.speedMetersPerSecond;
    if (speed != null &&
        speed > profile.policy.maxReliableSpeedMetersPerSecond) {
      warnings.add('Reported speed is unrealistic for ${profile.name}.');
    }

    return warnings.isEmpty
        ? const TransportValidationResult.valid()
        : TransportValidationResult.invalid(warnings);
  }

  MultiTransportModule mergeProfiles(
    Map<TransportType, TransportProfile> overrides,
  ) {
    return MultiTransportModule(profiles: {..._profiles, ...overrides});
  }

  static TransportPolicy _publicPassengerPolicy({
    required double movementThresholdMeters,
    required double geofenceRadiusMeters,
  }) {
    return TransportPolicy(
      movementThresholdMeters: movementThresholdMeters,
      geofenceRadiusMeters: geofenceRadiusMeters,
      maxReliableSpeedMetersPerSecond: 35,
      staleLocationAfter: const Duration(seconds: 30),
      emergencyPriorityEnabled: true,
      routeAwarenessRequired: true,
    );
  }
}
