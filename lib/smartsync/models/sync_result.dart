class SyncResult {
  final bool success;
  final int statusCode;
  final String? message;
  final DateTime completedAt;

  const SyncResult({
    required this.success,
    required this.statusCode,
    required this.completedAt,
    this.message,
  });
}
