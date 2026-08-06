import 'smartsync_enums.dart';

class BatteryState {
  final int levelPercent;
  final bool isCharging;
  final bool isPowerSaveMode;
  final BatteryMode mode;

  const BatteryState({
    required this.levelPercent,
    required this.isCharging,
    this.isPowerSaveMode = false,
    required this.mode,
  });
}
