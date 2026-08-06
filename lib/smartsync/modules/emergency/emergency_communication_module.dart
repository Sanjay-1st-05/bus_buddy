import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';
import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/models/sync_decision.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_event.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_rules.dart';
import 'package:esec_bus/smartsync/modules/emergency/emergency_sync_result.dart';

class EmergencyCommunicationModule implements SmartSyncEmergencyCoordinator {
  final EmergencyRules rules;

  const EmergencyCommunicationModule({
    this.rules = const EmergencyRules.defaults(),
  });

  factory EmergencyCommunicationModule.fromConfig(SmartSyncConfig config) {
    return EmergencyCommunicationModule(
      rules: EmergencyRules(
        emergencyPriorityEnabled: config.emergencyPriorityEnabled,
        aggressiveRetryCount:
            const EmergencyRules.defaults().aggressiveRetryCount,
        aggressiveRetryDelays:
            const EmergencyRules.defaults().aggressiveRetryDelays,
        bypassCompression: const EmergencyRules.defaults().bypassCompression,
        bypassSyncInterval: const EmergencyRules.defaults().bypassSyncInterval,
      ),
    );
  }

  @override
  EmergencySyncResult handle(EmergencyEvent event) {
    if (!rules.emergencyPriorityEnabled) {
      return EmergencySyncResult(
        event: event,
        decision: const SyncDecision.wait(
          Duration.zero,
          reason: 'emergency_priority_disabled',
        ),
        maxRetryCount: 0,
        retryDelays: const [],
        shouldBypassNormalInterval: false,
        shouldBypassCompression: false,
        reason: 'emergency_priority_disabled',
      );
    }

    return EmergencySyncResult(
      event: event,
      decision: const SyncDecision(
        action: SyncAction.emergencySend,
        reason: 'emergency_triggered',
        shouldCompress: false,
        isEmergency: true,
      ),
      maxRetryCount: rules.aggressiveRetryCount,
      retryDelays: rules.aggressiveRetryDelays,
      shouldBypassNormalInterval: rules.bypassSyncInterval,
      shouldBypassCompression: rules.bypassCompression,
      reason: 'emergency_sync_required',
    );
  }
}
