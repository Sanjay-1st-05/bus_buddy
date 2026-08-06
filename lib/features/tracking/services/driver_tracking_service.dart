import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/features/tracking/services/smartsync_driver_tracking_service.dart';
import 'package:esec_bus/smartsync/configuration/byzra_brand.dart';
import 'package:esec_bus/shared/models/bus_record.dart';

class DriverBusAssignment {
  final BusRecord bus;

  const DriverBusAssignment({required this.bus});

  String get busId => bus.id;
  String get busNo => bus.busNo;
  String get routeNo => bus.routeNo;
  String get routeName => bus.routeName;
  bool get isActive => bus.active;
}

class DriverTripState {
  final bool isRunning;
  final String status;
  final String? driverId;
  final DateTime? lastUpdatedAt;

  const DriverTripState({
    required this.isRunning,
    required this.status,
    this.driverId,
    this.lastUpdatedAt,
  });

  bool canResetForDriver(String currentDriverId) {
    return isRunning && (driverId == null || driverId == currentDriverId);
  }

  factory DriverTripState.fromMap(Map<String, dynamic>? data) {
    final statusValue = data?["status"];
    final status = statusValue is String && statusValue.trim().isNotEmpty
        ? statusValue.trim().toLowerCase()
        : data?["isActive"] == true
        ? "running"
        : "stopped";

    final driverIdValue = data?["driverId"];
    final updatedAt = data?["lastUpdatedAt"] ?? data?["updatedAt"];

    return DriverTripState(
      isRunning: data?["isActive"] == true || status == "running",
      status: status,
      driverId: driverIdValue is String ? driverIdValue : null,
      lastUpdatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }
}

class DriverTrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<DriverBusAssignment?> getAssignedBus(String driverId) async {
    final userData = await _getDriverData(driverId);
    final assignment = firestoreMap(userData?["assignment"]);
    final busId = firestoreString(assignment["busId"]) ?? "";

    if (busId.isEmpty) {
      return null;
    }

    final busDoc = await _firestore
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .get();
    final busData = busDoc.data();

    if (!busDoc.exists || busData == null) {
      return null;
    }

    return DriverBusAssignment(
      bus: BusRecord(id: busId, data: busData),
    );
  }

  static Stream<DriverTripState> watchTripState(String busId) {
    return _firestore
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return DriverTripState.fromMap(
            data == null ? null : firestoreMap(data["tracking"]),
          );
        });
  }

  static Future<void> prepareFreshDriverSession({
    required String busId,
    required String driverId,
  }) async {
    final busRef = _firestore.collection(FirestoreCollections.buses).doc(busId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(busRef);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;

      final tracking = firestoreMap(data["tracking"]);
      final state = DriverTripState.fromMap(tracking);
      if (!state.canResetForDriver(driverId)) return;

      transaction.update(busRef, {
        "tracking.busId": busId,
        "tracking.driverId": driverId,
        "tracking.isActive": false,
        "tracking.status": "stopped",
        "tracking.tripStoppedAt": FieldValue.serverTimestamp(),
        "tracking.serviceHeartbeatAt": FieldValue.delete(),
        "tracking.lastUpdatedAt": FieldValue.serverTimestamp(),
        "tracking.smartSync.engine": ByZraBrand.name,
        "tracking.smartSync.decision": "fresh_driver_session",
        "tracking.smartSync.queuedOffline": false,
        "updatedAt": FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<bool> isAssignedBusActive(String busId) async {
    final busDoc = await _firestore
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .get();
    return busDoc.data()?["active"] == true;
  }

  static Future<SmartSyncLocationSyncResult> updateLiveLocation({
    required String busId,
    required String driverId,
    required double latitude,
    required double longitude,
    double? speedMetersPerSecond,
    double? headingDegrees,
    double? accuracyMeters,
    DateTime? capturedAt,
    bool markTripStarted = false,
    bool isEmergency = false,
  }) async {
    return SmartSyncDriverTrackingService.syncDriverLocation(
      busId: busId,
      driverId: driverId,
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: speedMetersPerSecond,
      headingDegrees: headingDegrees,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt,
      markTripStarted: markTripStarted,
      isEmergency: isEmergency,
      source: "driver_app",
    );
  }

  static Future<void> stopTrip({
    required String busId,
    required String driverId,
  }) async {
    await SmartSyncDriverTrackingService.stopTrip(
      busId: busId,
      driverId: driverId,
    );
  }

  static Future<Map<String, dynamic>?> _getDriverData(String driverId) async {
    final userDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(driverId)
        .get();
    final data = userDoc.data();

    if (!userDoc.exists || data?["role"] != "driver") {
      return null;
    }

    return data;
  }
}
