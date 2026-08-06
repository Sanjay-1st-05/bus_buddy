import 'package:esec_bus/smartsync/modules/health/health_check_result.dart';

abstract interface class SmartSyncHealthCheck {
  String get component;

  Future<HealthCheckResult> check();
}

class CallbackHealthCheck implements SmartSyncHealthCheck {
  @override
  final String component;
  final Future<HealthCheckResult> Function() _check;

  const CallbackHealthCheck({
    required this.component,
    required Future<HealthCheckResult> Function() check,
  }) : _check = check;

  @override
  Future<HealthCheckResult> check() => _check();
}
