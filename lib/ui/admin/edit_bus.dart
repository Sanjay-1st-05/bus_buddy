import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/ui/widgets/primary_button.dart';
import 'package:esec_bus/ui/widgets/info_card.dart';

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

  bool _isLoading = false;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusData();
  }

  Future<void> _loadBusData() async {
    final doc = await FirebaseFirestore.instance
        .collection("bus_master")
        .doc(widget.busId)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      busNoController.text = data["busNo"] ?? "";

      selectedRouteData = {
        "routeName": data["routeName"],
        "routeNo": data["routeNo"],
        "via": data["via"],
      };
    }

    setState(() => _initialLoading = false);
  }

  Future<void> _updateBus() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isLoading = true);

      await FirebaseFirestore.instance
          .collection("bus_master")
          .doc(widget.busId)
          .update({
            "busNo": busNoController.text.trim(),
            "routeName": selectedRouteData?["routeName"],
            "routeNo": selectedRouteData?["routeNo"],
            "via": selectedRouteData?["via"],
            "updatedAt": FieldValue.serverTimestamp(),
          });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Bus updated successfully")));

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
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
                        .collection("bus_routes")
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final routes = snapshot.data!.docs;

                      return DropdownButtonFormField<String>(
                        value: selectedRouteId,
                        decoration: const InputDecoration(
                          labelText: "Select Route",
                          border: OutlineInputBorder(),
                        ),
                        items: routes.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                              "${data["routeNo"]} - ${data["routeName"]}",
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedRouteId = value;
                            selectedRouteData =
                                routes
                                        .firstWhere((doc) => doc.id == value)
                                        .data()
                                    as Map<String, dynamic>;
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
                          onPressed: _updateBus,
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
