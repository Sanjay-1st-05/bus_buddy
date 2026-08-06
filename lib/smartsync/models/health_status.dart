import 'smartsync_enums.dart';

class HealthStatus {
  final int score;
  final HealthSeverity severity;
  final List<String> warnings;
  final List<String> recoverySuggestions;

  const HealthStatus({
    required this.score,
    required this.severity,
    this.warnings = const [],
    this.recoverySuggestions = const [],
  });
}
