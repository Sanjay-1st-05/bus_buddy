import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/health_status.dart';
import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/health/health_check.dart';
import 'package:esec_bus/smartsync/modules/health/health_check_result.dart';
import 'package:esec_bus/smartsync/modules/health/health_monitor_rules.dart';

class HealthMonitorModule implements SmartSyncHealthMonitor {
  final List<SmartSyncHealthCheck> checks;
  final HealthMonitorRules rules;

  const HealthMonitorModule({
    this.checks = const [],
    this.rules = const HealthMonitorRules.defaults(),
  });

  @override
  Future<HealthStatus> checkHealth() async {
    final results = <HealthCheckResult>[];

    for (final check in checks) {
      results.add(await _runCheck(check));
    }

    return evaluate(results);
  }

  HealthStatus evaluate(List<HealthCheckResult> results) {
    final score = _score(results);
    final severity = _severityFor(score, results);
    final warnings = results
        .where((result) => !result.isHealthy && result.warning != null)
        .map((result) => '${result.component}: ${result.warning}')
        .toList(growable: false);
    final recoverySuggestions = results
        .where(
          (result) => !result.isHealthy && result.recoverySuggestion != null,
        )
        .map((result) => '${result.component}: ${result.recoverySuggestion}')
        .toSet()
        .toList(growable: false);

    return HealthStatus(
      score: score,
      severity: severity,
      warnings: warnings,
      recoverySuggestions: recoverySuggestions,
    );
  }

  Future<HealthCheckResult> _runCheck(SmartSyncHealthCheck check) async {
    try {
      return await check.check();
    } on Object catch (error) {
      return HealthCheckResult.unhealthy(
        component: check.component,
        severity: HealthSeverity.critical,
        warning: 'Health check failed: $error',
        recoverySuggestion: 'Restart the component and inspect diagnostics.',
      );
    }
  }

  int _score(List<HealthCheckResult> results) {
    final totalPenalty = results
        .where((result) => !result.isHealthy)
        .map((result) => rules.penaltyFor(result.severity))
        .fold<int>(0, (total, penalty) => total + penalty);

    return (rules.startingScore - totalPenalty).clamp(0, 100);
  }

  HealthSeverity _severityFor(int score, List<HealthCheckResult> results) {
    if (results.any(
          (result) =>
              !result.isHealthy && result.severity == HealthSeverity.critical,
        ) ||
        score <= rules.criticalScoreThreshold) {
      return HealthSeverity.critical;
    }

    if (results.any(
          (result) =>
              !result.isHealthy && result.severity == HealthSeverity.error,
        ) ||
        score <= rules.errorScoreThreshold) {
      return HealthSeverity.error;
    }

    if (results.any(
          (result) =>
              !result.isHealthy && result.severity == HealthSeverity.warning,
        ) ||
        score <= rules.warningScoreThreshold) {
      return HealthSeverity.warning;
    }

    return HealthSeverity.info;
  }
}
