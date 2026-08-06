class SecurityRules {
  final Duration timestampTolerance;
  final bool requireToken;
  final bool requireKnownDevice;
  final bool replayProtectionEnabled;

  const SecurityRules({
    required this.timestampTolerance,
    required this.requireToken,
    required this.requireKnownDevice,
    required this.replayProtectionEnabled,
  });

  const SecurityRules.defaults()
    : timestampTolerance = const Duration(minutes: 5),
      requireToken = true,
      requireKnownDevice = true,
      replayProtectionEnabled = true;
}
