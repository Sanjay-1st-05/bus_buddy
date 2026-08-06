import 'package:esec_bus/features/student/services/student_service.dart';
import 'package:test/test.dart';

void main() {
  test('reads the canonical assignment bus id', () {
    final profile = StudentProfile.fromMap(
      id: 'STUDENT_01',
      data: {
        'assignment': {'busId': 'BUS_01'},
      },
    );

    expect(profile.assignedBusId, 'BUS_01');
  });

  test('supports the existing top-level bus id during schema transition', () {
    final profile = StudentProfile.fromMap(
      id: 'STUDENT_01',
      data: {'busId': 'BUS_03'},
    );

    expect(profile.assignedBusId, 'BUS_03');
  });
}
