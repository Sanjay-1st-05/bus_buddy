import 'package:esec_bus/smartsync/models/smartsync_enums.dart';

class HealthMonitorRules {
  final int startingScore;
  final Map<HealthSeverity, int> penalties;
  final int warningScoreThreshold;
  final int errorScoreThreshold;
  final int criticalScoreThreshold;

  const HealthMonitorRules({
    required this.startingScore,
    required this.penalties,
    required this.warningScoreThreshold,
    required this.errorScoreThreshold,
    required this.criticalScoreThreshold,
  });

  const HealthMonitorRules.defaults()
    : startingScore = 100,
      penalties = const {
        HealthSeverity.info: 0,
        HealthSeverity.warning: 10,
        HealthSeverity.error: 25,
        HealthSeverity.critical: 50,
      },
      warningScoreThreshold = 85,
      errorScoreThreshold = 60,
      criticalScoreThreshold = 30;

  int penaltyFor(HealthSeverity severity) {
    return penalties[severity] ?? 0;
  }
}
