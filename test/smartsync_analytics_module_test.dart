import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  test('SmartSyncAnalyticsModule counts and retains runtime events', () {
    final analytics = SmartSyncAnalyticsModule(maxRecentEvents: 2);

    analytics.record('decision.sendNow', {'reason': 'ready'});
    analytics.record('decision.wait', {'reason': 'interval'});
    analytics.record('decision.sendNow', {'reason': 'movement'});

    expect(analytics.eventCounts['decision.sendNow'], 2);
    expect(analytics.eventCounts['decision.wait'], 1);
    expect(analytics.recentEvents, hasLength(2));
    expect(analytics.recentEvents.first['reason'], 'movement');
  });
}
