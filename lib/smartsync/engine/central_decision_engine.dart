import 'package:esec_bus/smartsync/engine/decision_engine_rules.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/health_status.dart';
import 'package:esec_bus/smartsync/models/movement_state.dart';
import 'package:esec_bus/smartsync/models/network_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/models/sync_decision.dart';

class CentralDecisionEngine implements SmartSyncDecisionEngine {
  final DecisionEngineRules rules;

  const CentralDecisionEngine({required this.rules});

  factory CentralDecisionEngine.defaults() {
    return CentralDecisionEngine(rules: DecisionEngineRules.defaults());
  }

  @override
  SyncDecision decide(SmartSyncDecisionContext context) {
    if (_shouldEmergencySync(context)) {
      return const SyncDecision.emergencySend(
        reason: 'emergency priority synchronization',
      );
    }

    if (!context.transportIsValid) {
      return SyncDecision.drop(
        reason: context.transportWarning ?? 'transport validation failed',
      );
    }

    if (!context.sample.hasValidCoordinates) {
      return const SyncDecision.drop(reason: 'invalid gps coordinates');
    }

    if (context.offlineQueueSize >= rules.config.maxOfflineQueueSize) {
      return const SyncDecision.drop(reason: 'offline queue capacity reached');
    }

    if (context.networkStatus.isOffline) {
      return const SyncDecision.queueOffline(reason: 'network offline');
    }

    if (context.retryCount >= rules.config.maxRetryCount) {
      return const SyncDecision.queueOffline(
        reason: 'maximum retry count reached',
      );
    }

    if (_hasCriticalHealth(context.healthStatus)) {
      return SyncDecision.wait(
        rules.healthRecoveryDelay,
        reason: 'critical ByZra health status',
      );
    }

    if (context.batteryState.mode == BatteryMode.emergencySaving) {
      return SyncDecision.wait(
        rules.emergencySavingDelay,
        reason: 'battery emergency saving mode',
      );
    }

    if (!context.synchronizationDue) {
      return SyncDecision.wait(
        context.synchronizationDelay,
        reason: 'adaptive synchronization interval not reached',
      );
    }

    if (!_movementRequiresSync(context.movementState)) {
      return SyncDecision.wait(
        _intervalFor(context.networkStatus),
        reason: 'movement threshold not reached',
      );
    }

    return SyncDecision.sendNow(
      reason: 'network, movement, battery, and health accepted',
      shouldCompress: _shouldCompress(context),
    );
  }

  bool _shouldEmergencySync(SmartSyncDecisionContext context) {
    return context.isEmergency && rules.config.emergencyPriorityEnabled;
  }

  bool _hasCriticalHealth(HealthStatus status) {
    return status.severity == HealthSeverity.critical;
  }

  bool _movementRequiresSync(MovementState state) {
    if (state.type == MovementType.stopped ||
        state.type == MovementType.idle ||
        state.type == MovementType.parked) {
      return state.passesThreshold(rules.config.movementThresholdMeters);
    }

    return true;
  }

  Duration _intervalFor(NetworkStatus status) {
    final interval = rules.config.intervalFor(status.quality);
    if (interval == Duration.zero) {
      return const Duration(seconds: 5);
    }
    return interval;
  }

  bool _shouldCompress(SmartSyncDecisionContext context) {
    return context.networkStatus.quality == NetworkQuality.average ||
        context.networkStatus.quality == NetworkQuality.weak ||
        context.batteryState.mode == BatteryMode.powerSaving ||
        context.batteryState.mode == BatteryMode.emergencySaving;
  }
}
