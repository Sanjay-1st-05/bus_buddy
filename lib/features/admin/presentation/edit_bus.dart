import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/shared/widgets/primary_button.dart';
import 'package:esec_bus/shared/widgets/info_card.dart';

class EditBusPage extends StatefulWidget {
  final String busId;

  const EditBusPage({super.key, required this.busId});

  @override
  State<EditBusPage> createState() => _EditBusPageState();
}

class _EditBusPageState extends State<EditBusPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController busNoController = TextEditingController();

  String? selectedRouteId;
  Map<String, dynamic>? selectedRouteData;
  bool _isTripRunning = false;

  bool _isLoading = false;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusData();
  }

  Future<void> _loadBusData() async {
    final doc = await FirebaseFirestore.instance
        .collection(FirestoreCollections.buses)
        .doc(widget.busId)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      busNoController.text = data["busNo"] ?? "";
      selectedRouteId = widget.busId;
      selectedRouteData = firestoreMap(data["route"]);
      _isTripRunning = firestoreMap(data["tracking"])["isActive"] == true;
    }

    if (mounted) {
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _updateBus() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isLoading = true);

      final busDoc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.buses)
          .doc(widget.busId)
          .get();

      if (firestoreMap(busDoc.data()?["tracking"])["isActive"] == true) {
        _showMessage("Stop the running trip before editing this bus");
        return;
      }

      final busRef = FirebaseFirestore.instance
          .collection(FirestoreCollections.buses)
          .doc(widget.busId);

      await busRef.update({
        "busNo": busNoController.text.trim(),
        "route": selectedRouteData ?? const <String, dynamic>{},
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Bus updated successfully")));

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    busNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Bus")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const InfoCard(
              title: "Edit Bus Information",
              subtitle: "Modify bus details below",
              icon: Icons.edit,
            ),
            if (_isTripRunning) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  "This bus has a running trip. Stop the trip before editing.",
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
            const SizedBox(height: 20),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  /// BUS ID (READ ONLY)
                  TextFormField(
                    initialValue: widget.busId,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: "Bus ID",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  /// BUS NUMBER
                  TextFormField(
                    controller: busNoController,
                    decoration: const InputDecoration(
                      labelText: "Bus Number",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? "Bus number required" : null,
                  ),
                  const SizedBox(height: 16),

                  /// ROUTE DROPDOWN
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection(FirestoreCollections.buses)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final routes = snapshot.data!.docs;

                      return DropdownButtonFormField<String>(
                        initialValue: selectedRouteId,
                        decoration: const InputDecoration(
                          labelText: "Select Route",
                          border: OutlineInputBorder(),
                        ),
                        items: routes.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final route = firestoreMap(data["route"]);

                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                              "${route["routeNo"]} - ${route["routeName"]}",
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedRouteId = value;
                            final selectedData =
                                routes
                                        .firstWhere((doc) => doc.id == value)
                                        .data()
                                    as Map<String, dynamic>;
                            selectedRouteData = firestoreMap(
                              selectedData["route"],
                            );
                          });
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  _isLoading
                      ? const CircularProgressIndicator()
                      : PrimaryButton(
                          text: "Update Bus",
                          icon: Icons.save,
                          onPressed: _isTripRunning ? null : _updateBus,
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
