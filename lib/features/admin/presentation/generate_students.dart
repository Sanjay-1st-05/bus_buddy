import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/core/services/user_provisioning_service.dart';
import 'package:esec_bus/shared/widgets/primary_button.dart';

class BulkStudentGenerator extends StatefulWidget {
  const BulkStudentGenerator({super.key});

  @override
  State<BulkStudentGenerator> createState() => _BulkStudentGeneratorState();
}

class _BulkStudentGeneratorState extends State<BulkStudentGenerator>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// BULK INPUTS
  final yearController = TextEditingController();
  final deptController = TextEditingController();
  final startRollController = TextEditingController();
  final endRollController = TextEditingController();

  /// SINGLE INPUTS
  final singleRollController = TextEditingController();
  final singleDeptController = TextEditingController();
  final singleYearController = TextEditingController();

  /// ASSIGN EXISTING STUDENT
  final existingStudentIdController = TextEditingController();

  String? selectedBulkBusId;
  String? selectedSingleBusId;
  String? selectedExistingStudentBusId;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    yearController.dispose();
    deptController.dispose();
    startRollController.dispose();
    endRollController.dispose();
    singleRollController.dispose();
    singleDeptController.dispose();
    singleYearController.dispose();
    existingStudentIdController.dispose();
    super.dispose();
  }

  /// 🔥 COMMON PASSWORD
  Future<String> _getDefaultPassword() async {
    final doc = await FirebaseFirestore.instance
        .collection(FirestoreCollections.appSettings)
        .doc("student_config")
        .get();

    return doc["defaultPassword"];
  }

  /// 🔥 BULK GENERATION
  Future<void> _generateBulkStudents() async {
    setState(() => loading = true);

    try {
      final year = yearController.text.trim();
      final dept = deptController.text.trim().toLowerCase();
      final start = int.parse(startRollController.text);
      final end = int.parse(endRollController.text);

      final password = await _getDefaultPassword();
      final assignment = await _buildAssignmentData(selectedBulkBusId);

      final users = <Map<String, Object?>>[];
      for (int i = start; i <= end; i++) {
        final roll = i.toString().padLeft(2, '0');
        final id = "es$year$dept$roll";
        users.add({
          "userId": id,
          "password": password,
          "role": "student",
          "profile": <String, Object?>{
            "year": year,
            "department": dept,
            "rollNumber": roll,
          },
          if (assignment.isNotEmpty)
            "assignment": <String, Object?>{"busId": assignment["busId"]},
        });
      }

      for (var offset = 0; offset < users.length; offset += 100) {
        final endOffset = (offset + 100).clamp(0, users.length);
        await UserProvisioningService.provisionMany(
          users.sublist(offset, endOffset),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bulk students created successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 🔥 SINGLE STUDENT ADD
  Future<void> _addSingleStudent() async {
    setState(() => loading = true);

    try {
      final year = singleYearController.text.trim();
      final dept = singleDeptController.text.trim().toLowerCase();
      final roll = singleRollController.text.trim().padLeft(2, '0');

      final id = "es$year$dept$roll";
      final password = await _getDefaultPassword();
      final assignment = await _buildAssignmentData(selectedSingleBusId);

      await UserProvisioningService.provision(
        userId: id,
        password: password,
        role: "student",
        profile: {"year": year, "department": dept, "rollNumber": roll},
        assignment: assignment.isEmpty
            ? const {}
            : <String, Object?>{"busId": assignment["busId"]},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Student $id added")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _assignExistingStudentBus() async {
    final studentId = existingStudentIdController.text.trim();

    if (studentId.isEmpty) {
      _showMessage("Student ID required");
      return;
    }

    if (selectedExistingStudentBusId == null) {
      _showMessage("Please select a bus");
      return;
    }

    setState(() => loading = true);

    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(studentId)
          .get();

      if (!studentDoc.exists || studentDoc.data()?["role"] != "student") {
        _showMessage("Student not found");
        return;
      }

      final assignment = await _buildAssignmentData(
        selectedExistingStudentBusId,
      );

      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(studentId)
          .set({
            "assignment": assignment,
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      _showMessage("Bus assigned to $studentId", success: true);
    } catch (e) {
      _showMessage("Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<Map<String, dynamic>> _buildAssignmentData(String? busId) async {
    if (busId == null) return {};

    final busDoc = await FirebaseFirestore.instance
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .get();
    final busData = busDoc.data();

    if (!busDoc.exists || busData == null) {
      throw Exception("Selected bus not found");
    }

    return {"busId": busId, "assignedAt": FieldValue.serverTimestamp()};
  }

  void _showMessage(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }

  Widget _input(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _busDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.buses)
          .where("active", isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final buses = snapshot.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String?>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.directions_bus),
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text("No assigned bus"),
              ),
              ...buses.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final busNo = data["busNo"] ?? doc.id;
                final route = firestoreMap(data["route"]);
                final routeNo = route["routeNo"] ?? "";
                final routeName = route["routeName"] ?? "";

                return DropdownMenuItem<String?>(
                  value: doc.id,
                  child: Text("$busNo - $routeNo $routeName"),
                );
              }),
            ],
            onChanged: snapshot.connectionState == ConnectionState.waiting
                ? null
                : onChanged,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Student Management"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Bulk Generate"),
            Tab(text: "Add Single"),
            Tab(text: "Assign Bus"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          /// ================= BULK =================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _input(yearController, "Year (e.g. 24)"),
                _input(deptController, "Department (cs, it...)"),
                _input(startRollController, "Start Roll No"),
                _input(endRollController, "End Roll No"),
                _busDropdown(
                  label: "Assign Bus (Optional)",
                  value: selectedBulkBusId,
                  onChanged: (value) {
                    setState(() => selectedBulkBusId = value);
                  },
                ),
                const SizedBox(height: 20),
                loading
                    ? const CircularProgressIndicator()
                    : PrimaryButton(
                        text: "Generate Students",
                        icon: Icons.groups,
                        onPressed: _generateBulkStudents,
                      ),
              ],
            ),
          ),

          /// ================= SINGLE =================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _input(singleYearController, "Year (e.g. 24)"),
                _input(singleDeptController, "Department"),
                _input(singleRollController, "Roll No"),
                _busDropdown(
                  label: "Assign Bus (Optional)",
                  value: selectedSingleBusId,
                  onChanged: (value) {
                    setState(() => selectedSingleBusId = value);
                  },
                ),
                const SizedBox(height: 20),
                loading
                    ? const CircularProgressIndicator()
                    : PrimaryButton(
                        text: "Add Student",
                        icon: Icons.person_add,
                        onPressed: _addSingleStudent,
                      ),
              ],
            ),
          ),

          /// ================= ASSIGN EXISTING =================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _input(existingStudentIdController, "Student ID"),
                _busDropdown(
                  label: "Assign Bus",
                  value: selectedExistingStudentBusId,
                  onChanged: (value) {
                    setState(() => selectedExistingStudentBusId = value);
                  },
                ),
                const SizedBox(height: 20),
                loading
                    ? const CircularProgressIndicator()
                    : PrimaryButton(
                        text: "Assign Bus",
                        icon: Icons.directions_bus,
                        onPressed: _assignExistingStudentBus,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
