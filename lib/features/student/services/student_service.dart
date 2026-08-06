import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/shared/models/bus_record.dart';

class StudentProfile {
  final String id;
  final String? assignedBusId;
  final String? routeNo;
  final String? routeName;
  final Map<String, dynamic> data;

  const StudentProfile({
    required this.id,
    this.assignedBusId,
    this.routeNo,
    this.routeName,
    this.data = const {},
  });

  bool get hasAssignedBus => assignedBusId != null;

  factory StudentProfile.fromMap({
    required String id,
    required Map<String, dynamic> data,
    BusRecord? assignedBus,
  }) {
    final assignment = firestoreMap(data["assignment"]);

    return StudentProfile(
      id: id,
      assignedBusId:
          _readString(assignment["busId"]) ?? _readString(data["busId"]),
      routeNo: assignedBus?.routeNo,
      routeName: assignedBus?.routeName,
      data: Map.unmodifiable(data),
    );
  }

  static String? _readString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}

class StudentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<StudentProfile?> getProfile(String studentId) async {
    final userDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(studentId)
        .get();
    final data = userDoc.data();

    if (!userDoc.exists || data == null) {
      return null;
    }

    final assignment = firestoreMap(data["assignment"]);
    final assignedBusId = firestoreString(assignment["busId"]);
    BusRecord? assignedBus;

    if (assignedBusId != null) {
      final busDoc = await _firestore
          .collection(FirestoreCollections.buses)
          .doc(assignedBusId)
          .get();
      final busData = busDoc.data();
      if (busDoc.exists && busData != null) {
        assignedBus = BusRecord(id: busDoc.id, data: busData);
      }
    }

    return StudentProfile.fromMap(
      id: studentId,
      data: data,
      assignedBus: assignedBus,
    );
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> activeBusesStream() {
    return _firestore
        .collection(FirestoreCollections.buses)
        .where("active", isEqualTo: true)
        .snapshots();
  }
}
