import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('HealthMonitorModule', () {
    test('returns a healthy status when all checks pass', () async {
      final module = HealthMonitorModule(
        checks: [
          CallbackHealthCheck(
            component: 'gps',
            check: () async => HealthCheckResult.healthy(component: 'gps'),
          ),
          CallbackHealthCheck(
            component: 'network',
            check: () async => HealthCheckResult.healthy(component: 'network'),
          ),
        ],
      );

      final status = await module.checkHealth();

      expect(status.score, 100);
      expect(status.severity, HealthSeverity.info);
      expect(status.warnings, isEmpty);
      expect(status.recoverySuggestions, isEmpty);
    });

    test('deducts score and exposes warnings for unhealthy checks', () async {
      final module = HealthMonitorModule(
        checks: [
          CallbackHealthCheck(
            component: 'gps',
            check: () async => HealthCheckResult.unhealthy(
              component: 'gps',
              severity: HealthSeverity.warning,
              warning: 'GPS accuracy is low',
              recoverySuggestion: 'Move to an open area.',
            ),
          ),
          CallbackHealthCheck(
            component: 'offlineQueue',
            check: () async => HealthCheckResult.unhealthy(
              component: 'offlineQueue',
              severity: HealthSeverity.error,
              warning: 'Offline queue is near capacity',
              recoverySuggestion: 'Sync queued packets when network improves.',
            ),
          ),
        ],
      );

      final status = await module.checkHealth();

      expect(status.score, 65);
      expect(status.severity, HealthSeverity.error);
      expect(status.warnings, [
        'gps: GPS accuracy is low',
        'offlineQueue: Offline queue is near capacity',
      ]);
      expect(status.recoverySuggestions, [
        'gps: Move to an open area.',
        'offlineQueue: Sync queued packets when network improves.',
      ]);
    });

    test('turns thrown check failures into critical health results', () async {
      final module = HealthMonitorModule(
        checks: [
          CallbackHealthCheck(
            component: 'firebase',
            check: () => Future<HealthCheckResult>.error(
              Exception('connection refused'),
            ),
          ),
        ],
      );

      final status = await module.checkHealth();

      expect(status.score, 50);
      expect(status.severity, HealthSeverity.critical);
      expect(status.warnings.single, contains('firebase: Health check failed'));
      expect(
        status.recoverySuggestions.single,
        'firebase: Restart the component and inspect diagnostics.',
      );
    });

    test('can evaluate externally collected health check results', () {
      const module = HealthMonitorModule();

      final status = module.evaluate([
        HealthCheckResult.unhealthy(
          component: 'battery',
          severity: HealthSeverity.critical,
          warning: 'Battery is in emergency saving mode',
          recoverySuggestion: 'Reduce GPS and sync frequency.',
        ),
      ]);

      expect(status.score, 50);
      expect(status.severity, HealthSeverity.critical);
      expect(status.warnings.single, contains('battery:'));
    });

    test('keeps recovery suggestions tied to their components', () async {
      final module = HealthMonitorModule(
        checks: [
          CallbackHealthCheck(
            component: 'gps',
            check: () async => HealthCheckResult.unhealthy(
              component: 'gps',
              severity: HealthSeverity.warning,
              warning: 'GPS weak',
              recoverySuggestion: 'Retry after recovery.',
            ),
          ),
          CallbackHealthCheck(
            component: 'network',
            check: () async => HealthCheckResult.unhealthy(
              component: 'network',
              severity: HealthSeverity.warning,
              warning: 'Network weak',
              recoverySuggestion: 'Retry after recovery.',
            ),
          ),
        ],
      );

      final status = await module.checkHealth();

      expect(status.warnings, hasLength(2));
      expect(status.recoverySuggestions, hasLength(2));
      expect(
        status.recoverySuggestions,
        containsAll([
          'gps: Retry after recovery.',
          'network: Retry after recovery.',
        ]),
      );
    });

    test('clamps health score at zero for many critical failures', () {
      const module = HealthMonitorModule();

      final status = module.evaluate([
        for (var i = 0; i < 4; i++)
          HealthCheckResult.unhealthy(
            component: 'component-$i',
            severity: HealthSeverity.critical,
            warning: 'critical failure',
            recoverySuggestion: 'restart component',
          ),
      ]);

      expect(status.score, 0);
      expect(status.severity, HealthSeverity.critical);
    });
  });
}
