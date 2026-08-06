import 'package:esec_bus/features/tracking/services/driver_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverTripState fresh dashboard session', () {
    test('allows the signed-in driver to clear their running trip', () {
      final state = DriverTripState.fromMap({
        'isActive': true,
        'status': 'running',
        'driverId': 'DRV_BUS_01',
      });

      expect(state.canResetForDriver('DRV_BUS_01'), isTrue);
    });

    test('does not clear a trip owned by another driver', () {
      final state = DriverTripState.fromMap({
        'isActive': true,
        'status': 'running',
        'driverId': 'DRV_BUS_02',
      });

      expect(state.canResetForDriver('DRV_BUS_01'), isFalse);
    });

    test('does not reset an already stopped trip', () {
      final state = DriverTripState.fromMap({
        'isActive': false,
        'status': 'stopped',
        'driverId': 'DRV_BUS_01',
      });

      expect(state.canResetForDriver('DRV_BUS_01'), isFalse);
    });
  });
}
