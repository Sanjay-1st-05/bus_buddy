import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';

class SmartSyncAnalyticsModule implements SmartSyncTelemetrySink {
  final Map<String, int> _eventCounts = {};
  final List<Map<String, Object?>> _recentEvents = [];
  final int maxRecentEvents;

  SmartSyncAnalyticsModule({this.maxRecentEvents = 50});

  @override
  void record(String eventName, Map<String, Object?> data) {
    _eventCounts[eventName] = (_eventCounts[eventName] ?? 0) + 1;
    _recentEvents.insert(0, {
      'name': eventName,
      'recordedAt': DateTime.now().toIso8601String(),
      ...data,
    });
    if (_recentEvents.length > maxRecentEvents) {
      _recentEvents.removeRange(maxRecentEvents, _recentEvents.length);
    }
  }

  Map<String, int> get eventCounts => Map.unmodifiable(_eventCounts);

  List<Map<String, Object?>> get recentEvents =>
      List.unmodifiable(_recentEvents);
}
