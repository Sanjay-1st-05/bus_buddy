class BatteryReading {
  final int levelPercent;
  final bool isCharging;
  final bool isPowerSaveMode;
  final DateTime measuredAt;

  const BatteryReading({
    required this.levelPercent,
    required this.isCharging,
    this.isPowerSaveMode = false,
    required this.measuredAt,
  });
}
