import 'package:esec_bus/smartsync/debug/smartsync_debug.dart';
import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ByZra dashboard renders initial debug state', (tester) async {
    final controller = SmartSyncDebugController(
      initialState: SmartSyncDebugState.initial(now: DateTime.utc(2026, 7, 11)),
    );

    await tester.pumpWidget(
      MaterialApp(home: SmartSyncDeveloperDashboard(controller: controller)),
    );

    expect(find.text('ByZra Developer Dashboard'), findsOneWidget);
    expect(find.text('Current Network Quality'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Current Synchronization Interval'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Current Engine Decision'), findsOneWidget);
    expect(find.text('Queue Offline'), findsOneWidget);
    expect(find.text('Value Source'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);

    await controller.dispose();
  });

  testWidgets('ByZra dashboard updates when controller emits state', (
    tester,
  ) async {
    final controller = SmartSyncDebugController(
      initialState: SmartSyncDebugState.initial(now: DateTime.utc(2026, 7, 11)),
    );

    await tester.pumpWidget(
      MaterialApp(home: SmartSyncDeveloperDashboard(controller: controller)),
    );

    controller.updateWith(
      (state) => state.copyWith(
        networkStatus: NetworkStatus(
          quality: NetworkQuality.good,
          latency: const Duration(milliseconds: 250),
          packetLossPercent: 2,
          signalStability: 0.82,
          measuredAt: DateTime.utc(2026, 7, 11, 10),
        ),
        synchronizationInterval: const Duration(seconds: 5),
        engineDecision: const SyncDecision.sendNow(reason: 'movement accepted'),
        retryCount: 1,
        offlineQueueSize: 3,
        gpsAccuracyMeters: 7.5,
        movementState: const MovementState(
          type: MovementType.moving,
          distanceSinceLastSyncMeters: 26,
        ),
        batteryState: const BatteryState(
          levelPercent: 48,
          isCharging: false,
          mode: BatteryMode.balanced,
        ),
        activeModules: const ['network', 'synchronization', 'movement'],
        valueSources: const {
          'networkQuality': SmartSyncDebugValueSource.live,
          'latency': SmartSyncDebugValueSource.live,
          'packetLoss': SmartSyncDebugValueSource.live,
          'signalStability': SmartSyncDebugValueSource.live,
          'syncInterval': SmartSyncDebugValueSource.derived,
          'engineDecision': SmartSyncDebugValueSource.derived,
          'retryCount': SmartSyncDebugValueSource.fallback,
          'offlineQueueSize': SmartSyncDebugValueSource.fallback,
          'gpsAccuracy': SmartSyncDebugValueSource.fallback,
          'movementStatus': SmartSyncDebugValueSource.fallback,
          'batteryMode': SmartSyncDebugValueSource.fallback,
          'activeModules': SmartSyncDebugValueSource.fallback,
        },
      ),
    );
    controller.addEvent('Decision emitted: sendNow');

    await tester.pump();

    expect(find.text('Good'), findsOneWidget);
    expect(find.text('250 ms'), findsOneWidget);
    expect(find.text('5 sec'), findsOneWidget);
    expect(find.text('Send Now'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Derived'), findsWidgets);
    expect(find.text('Unavailable'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pump();

    expect(find.text('7.5 m'), findsOneWidget);
    expect(find.text('Moving'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('network'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('network'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Decision emitted: sendNow'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Decision emitted: sendNow'), findsOneWidget);

    await controller.dispose();
  });
}
