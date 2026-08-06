import 'package:esec_bus/smartsync/models/battery_state.dart';

enum LocationPowerAccuracy { high, balanced, lowPower }

class LocationPowerProfile {
  final BatteryState batteryState;
  final Duration gpsInterval;
  final int distanceFilterMeters;
  final LocationPowerAccuracy accuracy;
  final String reason;

  const LocationPowerProfile({
    required this.batteryState,
    required this.gpsInterval,
    required this.distanceFilterMeters,
    required this.accuracy,
    required this.reason,
  });

  @override
  bool operator ==(Object other) {
    return other is LocationPowerProfile &&
        other.batteryState.mode == batteryState.mode &&
        other.batteryState.isPowerSaveMode == batteryState.isPowerSaveMode &&
        other.gpsInterval == gpsInterval &&
        other.distanceFilterMeters == distanceFilterMeters &&
        other.accuracy == accuracy;
  }

  @override
  int get hashCode => Object.hash(
    batteryState.mode,
    batteryState.isPowerSaveMode,
    gpsInterval,
    distanceFilterMeters,
    accuracy,
  );
}
