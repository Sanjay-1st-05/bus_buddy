class SecurityCredentials {
  final String deviceId;
  final String token;
  final String signingKeyId;

  const SecurityCredentials({
    required this.deviceId,
    required this.token,
    required this.signingKeyId,
  });
}
