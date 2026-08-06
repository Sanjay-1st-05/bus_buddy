enum SmartSyncDebugValueSource { live, derived, fallback }

extension SmartSyncDebugValueSourceLabel on SmartSyncDebugValueSource {
  String get label {
    return switch (this) {
      SmartSyncDebugValueSource.live => 'Live',
      SmartSyncDebugValueSource.derived => 'Derived',
      SmartSyncDebugValueSource.fallback => 'Unavailable',
    };
  }
}
