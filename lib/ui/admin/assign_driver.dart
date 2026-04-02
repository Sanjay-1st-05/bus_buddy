import 'package:flutter/material.dart';
import 'package:esec_bus/ui/widgets/primary_button.dart';
import 'package:esec_bus/ui/widgets/info_card.dart';

class AssignDriverPage extends StatefulWidget {
  const AssignDriverPage({super.key});

  @override
  State<AssignDriverPage> createState() => _AssignDriverPageState();
}

class _AssignDriverPageState extends State<AssignDriverPage> {
  final _formKey = GlobalKey<FormState>();

  String? selectedBus;
  String? selectedDriver;

  final List<String> busList = [
    "Bus 22A",
    "Bus 15B",
    "Bus 09C",
  ];

  final List<String> driverList = [
    "Ramesh Kumar",
    "Suresh Babu",
    "Arun Driver",
  ];

  void _assignDriver() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Driver assigned to $selectedBus (Demo)",
          ),
        ),
      );

      Navigator.pop(context);
    }
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
            /// HEADER CARD
            const InfoCard(
              title: "Driver Assignment",
              subtitle: "Select bus and driver",
              icon: Icons.assignment_ind,
            ),

            const SizedBox(height: 20),

            /// FORM
            Form(
              key: _formKey,
              child: Column(
                children: [
                  /// BUS DROPDOWN
                  DropdownButtonFormField<String>(
                    value: selectedBus,
                    items: busList
                        .map(
                          (bus) => DropdownMenuItem(
                            value: bus,
                            child: Text(bus),
                          ),
                        )
                        .toList(),
                    decoration: const InputDecoration(
                      labelText: "Select Bus",
                      prefixIcon: Icon(Icons.directions_bus),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        selectedBus = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? "Please select a bus" : null,
                  ),

                  const SizedBox(height: 16),

                  /// DRIVER DROPDOWN
                  DropdownButtonFormField<String>(
                    value: selectedDriver,
                    items: driverList
                        .map(
                          (driver) => DropdownMenuItem(
                            value: driver,
                            child: Text(driver),
                          ),
                        )
                        .toList(),
                    decoration: const InputDecoration(
                      labelText: "Select Driver",
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        selectedDriver = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? "Please select a driver" : null,
                  ),

                  const SizedBox(height: 24),

                  /// ASSIGN BUTTON
                  PrimaryButton(
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
