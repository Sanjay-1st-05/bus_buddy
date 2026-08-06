import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/core/services/user_provisioning_service.dart';
import 'package:esec_bus/shared/widgets/primary_button.dart';
import 'package:esec_bus/shared/widgets/info_card.dart';

class AddBusPage extends StatefulWidget {
  const AddBusPage({super.key});

  @override
  State<AddBusPage> createState() => _AddBusPageState();
}

class _AddBusPageState extends State<AddBusPage> {
  final _formKey = GlobalKey<FormState>();

  final busIdController = TextEditingController();
  final busNoController = TextEditingController();
  final routeNameController = TextEditingController();
  final routeNoController = TextEditingController();
  final startPointController = TextEditingController();
  final endPointController = TextEditingController();
  final viaController = TextEditingController();
  final stopsController = TextEditingController();

  final driverNameController = TextEditingController();
  final driverMobileController = TextEditingController();
  final driverPasswordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    busIdController.dispose();
    busNoController.dispose();
    routeNameController.dispose();
    routeNoController.dispose();
    startPointController.dispose();
    endPointController.dispose();
    viaController.dispose();
    stopsController.dispose();
    driverNameController.dispose();
    driverMobileController.dispose();
    driverPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveBus() async {
    if (!_formKey.currentState!.validate()) return;

    final busId = busIdController.text.trim().toUpperCase();
    final driverId = "drv_${busId.toLowerCase()}";
    final driverMobile = driverMobileController.text.trim();

    try {
      setState(() => _isLoading = true);
      final firestore = FirebaseFirestore.instance;
      final busRef = firestore
          .collection(FirestoreCollections.buses)
          .doc(busId);
      final driverRef = firestore
          .collection(FirestoreCollections.users)
          .doc(driverId);

      /// 🔍 CHECK BUS ALREADY EXISTS
      final busDoc = await busRef.get();

      if (busDoc.exists) {
        _showMsg("Bus ID already exists");
        return;
      }

      /// 🔍 CHECK DRIVER MOBILE DUPLICATE
      final driverQuery = await firestore
          .collection(FirestoreCollections.users)
          .where("profile.mobile", isEqualTo: driverMobile)
          .get();

      if (driverQuery.docs.isNotEmpty) {
        _showMsg("Driver mobile already registered");
        return;
      }

      if ((await driverRef.get()).exists) {
        _showMsg("Driver ID already exists");
        return;
      }

      final timestamp = FieldValue.serverTimestamp();
      final trackPoints = stopsController.text
          .split(',')
          .map((stop) => stop.trim())
          .where((stop) => stop.isNotEmpty)
          .toList(growable: false)
          .asMap()
          .entries
          .map((entry) {
            final parts = entry.value.split('|');
            final latitude = parts.length > 1
                ? double.tryParse(parts[1].trim())
                : null;
            final longitude = parts.length > 2
                ? double.tryParse(parts[2].trim())
                : null;
            return <String, Object?>{
              "stopId": "$busId-${entry.key}",
              "name": parts.first.trim().toUpperCase(),
              "sequence": entry.key,
              if (latitude != null) "latitude": latitude,
              if (longitude != null) "longitude": longitude,
            };
          })
          .toList(growable: false);

      await UserProvisioningService.provision(
        userId: driverId,
        password: driverPasswordController.text.trim(),
        role: "driver",
        profile: {
          "name": driverNameController.text.trim().toUpperCase(),
          "mobile": driverMobile,
        },
        assignment: {"busId": busId},
      );

      final batch = firestore.batch();

      batch.set(busRef, {
        "schemaVersion": FirestoreSchemaVersions.consolidated,
        "busId": busId,
        "active": true,
        "busNo": busNoController.text.trim(),
        "route": {
          "routeId": busId,
          "routeName": routeNameController.text.trim().toUpperCase(),
          "routeNo": routeNoController.text.trim(),
          "startPoint": startPointController.text.trim().toUpperCase(),
          "endPoint": endPointController.text.trim().toUpperCase(),
          "via": viaController.text.trim().toUpperCase(),
          "trackPoints": trackPoints,
        },
        "assignment": {"driverId": driverId, "assignedAt": timestamp},
        "tracking": {
          "busId": busId,
          "driverId": driverId,
          "currentPoint": {"latitude": 0.0, "longitude": 0.0},
          "isActive": false,
          "status": "stopped",
          "updatedAt": timestamp,
        },
        "createdAt": timestamp,
        "updatedAt": timestamp,
      });

      batch.update(driverRef, {
        "assignment": {"busId": busId, "assignedAt": timestamp},
        "updatedAt": timestamp,
      });

      await batch.commit();

      if (!mounted) return;
      _showMsg("Bus, Route & Driver added successfully", success: true);
      Navigator.pop(context);
    } catch (e) {
      _showMsg("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) =>
            v == null || v.trim().isEmpty ? "$label required" : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add New Bus")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const InfoCard(
              title: "Bus, Route & Driver Registration",
              subtitle: "Enter complete details",
              icon: Icons.directions_bus,
            ),
            const SizedBox(height: 20),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(busIdController, "Bus ID (BUS_01)"),
                  _field(busNoController, "Bus Number"),
                  _field(routeNameController, "Route Name"),
                  _field(routeNoController, "Route Number"),
                  _field(startPointController, "Start Point"),
                  _field(endPointController, "End Point"),
                  _field(viaController, "Via"),
                  _field(
                    stopsController,
                    "Stops: NAME|latitude|longitude, ...",
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),

                  const Text(
                    "Driver Details",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  _field(driverNameController, "Driver Name"),
                  _field(
                    driverMobileController,
                    "Driver Mobile",
                    type: TextInputType.phone,
                  ),
                  _field(driverPasswordController, "Temporary Password"),

                  const SizedBox(height: 30),

                  _isLoading
                      ? const CircularProgressIndicator()
                      : PrimaryButton(
                          text: "Save Bus",
                          icon: Icons.save,
                          onPressed: _saveBus,
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
