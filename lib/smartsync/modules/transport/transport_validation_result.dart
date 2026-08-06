class TransportValidationResult {
  final bool isValid;
  final List<String> warnings;

  const TransportValidationResult({
    required this.isValid,
    this.warnings = const [],
  });

  const TransportValidationResult.valid() : isValid = true, warnings = const [];

  const TransportValidationResult.invalid(this.warnings) : isValid = false;
}
