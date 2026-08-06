import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/shared/widgets/primary_button.dart';
import 'package:esec_bus/shared/widgets/info_card.dart';

class AssignDriverPage extends StatefulWidget {
  const AssignDriverPage({super.key});

  @override
  State<AssignDriverPage> createState() => _AssignDriverPageState();
}

class _AssignDriverPageState extends State<AssignDriverPage> {
  final _formKey = GlobalKey<FormState>();

  String? selectedBusId;
  String? selectedDriverId;
  bool _isLoading = false;

  Future<void> _assignDriver() async {
    if (!_formKey.currentState!.validate()) return;

    final busId = selectedBusId;
    final driverId = selectedDriverId;

    if (busId == null || driverId == null) {
      _showMessage("Select bus and driver");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final busRef = firestore
          .collection(FirestoreCollections.buses)
          .doc(busId);
      final driverRef = firestore
          .collection(FirestoreCollections.users)
          .doc(driverId);

      final busDoc = await busRef.get();
      final driverDoc = await driverRef.get();

      if (!busDoc.exists || busDoc.data()?["active"] != true) {
        _showMessage("Selected bus is inactive or missing");
        return;
      }

      if (!driverDoc.exists ||
          driverDoc.data()?["active"] != true ||
          driverDoc.data()?["role"] != "driver") {
        _showMessage("Selected driver is inactive or missing");
        return;
      }

      final busData = busDoc.data()!;
      final driverData = driverDoc.data()!;
      final tracking = firestoreMap(busData["tracking"]);

      if (tracking["isActive"] == true) {
        _showMessage("Stop the current trip before reassigning this bus");
        return;
      }

      final previousBusId = _readString(
        firestoreMap(driverData["assignment"])["busId"],
      );
      final previousDriverId = _readString(
        firestoreMap(busData["assignment"])["driverId"],
      );

      if (previousBusId != null && previousBusId != busId) {
        final previousBusDoc = await firestore
            .collection(FirestoreCollections.buses)
            .doc(previousBusId)
            .get();

        if (firestoreMap(previousBusDoc.data()?["tracking"])["isActive"] ==
            true) {
          _showMessage("Stop driver's current trip before reassignment");
          return;
        }
      }

      final batch = firestore.batch();
      final assignedAt = FieldValue.serverTimestamp();

      if (previousDriverId != null && previousDriverId != driverId) {
        batch.update(
          firestore
              .collection(FirestoreCollections.users)
              .doc(previousDriverId),
          {
            "assignment": FieldValue.delete(),
            "updatedAt": assignedAt,
          },
        );
      }

      if (previousBusId != null && previousBusId != busId) {
        batch.update(
          firestore
              .collection(FirestoreCollections.buses)
              .doc(previousBusId),
          {
            "assignment": FieldValue.delete(),
            "tracking.driverId": FieldValue.delete(),
            "updatedAt": assignedAt,
          },
        );
      }

      batch.update(driverRef, {
        "assignment": {
          "busId": busId,
          "assignedAt": assignedAt,
        },
        "updatedAt": assignedAt,
      });

      batch.update(busRef, {
        "assignment": {
          "driverId": driverId,
          "assignedAt": assignedAt,
        },
        "tracking.busId": busId,
        "tracking.driverId": driverId,
        "tracking.isActive": false,
        "tracking.status": "stopped",
        "updatedAt": assignedAt,
      });

      await batch.commit();

      _showMessage("Driver assigned successfully", success: true);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showMessage("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _activeBusesStream() {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.buses)
        .where("active", isEqualTo: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _activeDriversStream() {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .where("role", isEqualTo: "driver")
        .where("active", isEqualTo: true)
        .snapshots();
  }

  void _showMessage(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  String? _readString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  String _busLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final busNo = (data["busNo"] ?? doc.id).toString();
    final route = firestoreMap(data["route"]);
    final routeNo = (route["routeNo"] ?? "").toString();
    final routeName = (route["routeName"] ?? "").toString();
    final driverId = _readString(
      firestoreMap(data["assignment"])["driverId"],
    );
    final assignment = driverId == null ? "Unassigned" : "Driver: $driverId";

    return "$busNo - $routeNo $routeName ($assignment)";
  }

  String _driverLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final profile = firestoreMap(data["profile"]);
    final name = (profile["name"] ?? doc.id).toString();
    final mobile = (profile["mobile"] ?? "").toString();
    final busId = _readString(firestoreMap(data["assignment"])["busId"]);
    final assignment = busId == null ? "Unassigned" : "Bus: $busId";

    return "$name ${mobile.isEmpty ? "" : "- $mobile"} ($assignment)";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Assign Driver",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InfoCard(
              title: "Driver Assignment",
              subtitle: "Select bus and driver",
              icon: Icons.assignment_ind,
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _activeBusesStream(),
                    builder: (context, snapshot) {
                      final buses = snapshot.data?.docs ?? [];

                      return DropdownButtonFormField<String>(
                        initialValue: selectedBusId,
                        isExpanded: true,
                        items: buses
                            .map(
                              (bus) => DropdownMenuItem(
                                value: bus.id,
                                child: Text(_busLabel(bus)),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: "Select Bus",
                          prefixIcon: Icon(Icons.directions_bus),
                          border: OutlineInputBorder(),
                        ),
                        onChanged:
                            snapshot.connectionState == ConnectionState.waiting
                            ? null
                            : (value) {
                                setState(() => selectedBusId = value);
                              },
                        validator: (value) =>
                            value == null ? "Please select a bus" : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _activeDriversStream(),
                    builder: (context, snapshot) {
                      final drivers = snapshot.data?.docs ?? [];

                      return DropdownButtonFormField<String>(
                        initialValue: selectedDriverId,
                        isExpanded: true,
                        items: drivers
                            .map(
                              (driver) => DropdownMenuItem(
                                value: driver.id,
                                child: Text(_driverLabel(driver)),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: "Select Driver",
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                        onChanged:
                            snapshot.connectionState == ConnectionState.waiting
                            ? null
                            : (value) {
                                setState(() => selectedDriverId = value);
                              },
                        validator: (value) =>
                            value == null ? "Please select a driver" : null,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : PrimaryButton(
                          text: "Assign Driver",
                          icon: Icons.check_circle,
                          onPressed: _assignDriver,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
