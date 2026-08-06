enum SmartSyncDebugEventLevel { info, warning, error }

class SmartSyncDebugEvent {
  final String message;
  final SmartSyncDebugEventLevel level;
  final DateTime occurredAt;

  const SmartSyncDebugEvent({
    required this.message,
    required this.level,
    required this.occurredAt,
  });
}
