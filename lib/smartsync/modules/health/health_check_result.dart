import 'package:esec_bus/smartsync/models/smartsync_enums.dart';

class HealthCheckResult {
  final String component;
  final bool isHealthy;
  final HealthSeverity severity;
  final String? warning;
  final String? recoverySuggestion;
  final DateTime checkedAt;
  final Map<String, Object?> metadata;

  const HealthCheckResult({
    required this.component,
    required this.isHealthy,
    required this.severity,
    required this.checkedAt,
    this.warning,
    this.recoverySuggestion,
    this.metadata = const {},
  });

  factory HealthCheckResult.healthy({
    required String component,
    DateTime? checkedAt,
    Map<String, Object?> metadata = const {},
  }) {
    return HealthCheckResult(
      component: component,
      isHealthy: true,
      severity: HealthSeverity.info,
      checkedAt: checkedAt ?? DateTime.now(),
      metadata: metadata,
    );
  }

  factory HealthCheckResult.unhealthy({
    required String component,
    required HealthSeverity severity,
    required String warning,
    required String recoverySuggestion,
    DateTime? checkedAt,
    Map<String, Object?> metadata = const {},
  }) {
    return HealthCheckResult(
      component: component,
      isHealthy: false,
      severity: severity,
      warning: warning,
      recoverySuggestion: recoverySuggestion,
      checkedAt: checkedAt ?? DateTime.now(),
      metadata: metadata,
    );
  }
}
