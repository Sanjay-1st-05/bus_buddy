import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/ui/widgets/primary_button.dart';
import 'package:esec_bus/ui/widgets/info_card.dart';

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
    super.dispose();
  }

  Future<void> _saveBus() async {
    if (!_formKey.currentState!.validate()) return;

    final busId = busIdController.text.trim().toUpperCase();
    final driverId = "DRV_$busId";
    final driverMobile = driverMobileController.text.trim();

    try {
      setState(() => _isLoading = true);

      /// 🔍 CHECK BUS ALREADY EXISTS
      final busDoc = await FirebaseFirestore.instance
          .collection("bus_master")
          .doc(busId)
          .get();

      if (busDoc.exists) {
        _showMsg("Bus ID already exists");
        return;
      }

      /// 🔍 CHECK DRIVER MOBILE DUPLICATE
      final driverQuery = await FirebaseFirestore.instance
          .collection("drivers")
          .where("mobile", isEqualTo: driverMobile)
          .get();

      if (driverQuery.docs.isNotEmpty) {
        _showMsg("Driver mobile already registered");
        return;
      }

      /// 🔥 ROUTE SAVE
      await FirebaseFirestore.instance.collection("bus_routes").doc(busId).set({
        "routeName": routeNameController.text.trim().toUpperCase(),
        "routeNo": routeNoController.text.trim(),
        "startPoint": startPointController.text.trim().toUpperCase(),
        "endPoint": endPointController.text.trim().toUpperCase(),
        "via": viaController.text.trim().toUpperCase(),
        "stops": stopsController.text
            .split(',')
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList(),
        "createdAt": FieldValue.serverTimestamp(),
      });

      /// 🔥 BUS MASTER SAVE
      await FirebaseFirestore.instance.collection("bus_master").doc(busId).set({
        "active": true,
        "busNo": busNoController.text.trim(),
        "routeName": routeNameController.text.trim().toUpperCase(),
        "routeNo": routeNoController.text.trim(),
        "via": viaController.text.trim().toUpperCase(),
        "driverId": driverId,
        "createdAt": FieldValue.serverTimestamp(),
      });

      /// 🔥 LOCATION INIT
      await FirebaseFirestore.instance
          .collection("bus_location")
          .doc(busId)
          .set({
            "latitude": 0.0,
            "longitude": 0.0,
            "isActive": false,
            "updatedAt": FieldValue.serverTimestamp(),
          });

      /// 🔥 DRIVER SAVE
      await FirebaseFirestore.instance.collection("drivers").doc(driverId).set({
        "driverName": driverNameController.text.trim().toUpperCase(),
        "mobile": driverMobile,
        "busId": busId,
        "active": true,
        "createdAt": FieldValue.serverTimestamp(),
      });

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
                  _field(stopsController, "Stops (comma separated)"),

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
