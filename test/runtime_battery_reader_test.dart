import 'package:esec_bus/smartsync/modules/battery/battery_reading.dart';
import 'package:esec_bus/smartsync/services/runtime_battery_reader.dart';
import 'package:test/test.dart';

void main() {
  test('caches the native battery reading between GPS samples', () async {
    var loadCount = 0;
    final reader = RuntimeBatteryReader(
      cacheDuration: const Duration(minutes: 2),
      loader: () async {
        loadCount++;
        return BatteryReading(
          levelPercent: 42,
          isCharging: false,
          isPowerSaveMode: true,
          measuredAt: DateTime.now(),
        );
      },
    );

    final first = await reader.read();
    final second = await reader.read();

    expect(first?.levelPercent, 42);
    expect(second?.isPowerSaveMode, isTrue);
    expect(loadCount, 1);
  });

  test('force refresh bypasses the battery cache', () async {
    var loadCount = 0;
    final reader = RuntimeBatteryReader(
      loader: () async {
        loadCount++;
        return BatteryReading(
          levelPercent: 80 - loadCount,
          isCharging: false,
          measuredAt: DateTime.now(),
        );
      },
    );

    await reader.read();
    final refreshed = await reader.read(forceRefresh: true);

    expect(refreshed?.levelPercent, 78);
    expect(loadCount, 2);
  });
}
