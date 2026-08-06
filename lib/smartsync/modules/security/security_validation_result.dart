import 'package:esec_bus/smartsync/modules/security/security_validation_status.dart';

class SecurityValidationResult {
  final bool isValid;
  final SecurityValidationStatus status;
  final String reason;

  const SecurityValidationResult({
    required this.isValid,
    required this.status,
    required this.reason,
  });

  const SecurityValidationResult.valid()
    : isValid = true,
      status = SecurityValidationStatus.valid,
      reason = 'valid';

  const SecurityValidationResult.invalid({
    required this.status,
    required this.reason,
  }) : isValid = false;
}
