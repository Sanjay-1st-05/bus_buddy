import 'package:esec_bus/smartsync/configuration/smartsync_config.dart';

class DecisionEngineRules {
  final SmartSyncConfig config;
  final Duration healthRecoveryDelay;
  final Duration emergencySavingDelay;

  const DecisionEngineRules({
    required this.config,
    required this.healthRecoveryDelay,
    required this.emergencySavingDelay,
  });

  factory DecisionEngineRules.defaults({SmartSyncConfig? config}) {
    return DecisionEngineRules(
      config: config ?? SmartSyncConfig.defaults(),
      healthRecoveryDelay: const Duration(seconds: 30),
      emergencySavingDelay: const Duration(seconds: 60),
    );
  }
}
