import 'package:battery_plus/battery_plus.dart' as platform;
import 'package:flutter/services.dart';

import 'package:esec_bus/smartsync/modules/battery/battery_reading.dart';

typedef BatteryReadingLoader = Future<BatteryReading?> Function();

class RuntimeBatteryReader {
  final BatteryReadingLoader? _loader;
  final Duration cacheDuration;
  final platform.Battery _battery;
  BatteryReading? _cached;

  RuntimeBatteryReader({
    BatteryReadingLoader? loader,
    this.cacheDuration = const Duration(minutes: 2),
  }) : _loader = loader,
       _battery = platform.Battery();

  Future<BatteryReading?> read({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cached = _cached;
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.measuredAt) < cacheDuration) {
      return cached;
    }

    try {
      final reading = await (_loader?.call() ?? _readPlatformBattery());
      if (reading != null) _cached = reading;
      return reading ?? cached;
    } on MissingPluginException {
      return cached;
    } on PlatformException {
      return cached;
    }
  }

  Future<BatteryReading?> _readPlatformBattery() async {
    final level = await _battery.batteryLevel;
    final state = await _battery.batteryState;
    final isPowerSaveMode = await _battery.isInBatterySaveMode;
    final isCharging =
        state == platform.BatteryState.charging ||
        state == platform.BatteryState.full;

    return BatteryReading(
      levelPercent: level,
      isCharging: isCharging,
      isPowerSaveMode: isPowerSaveMode,
      measuredAt: DateTime.now(),
    );
  }
}
