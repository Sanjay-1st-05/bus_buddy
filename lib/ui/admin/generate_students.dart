import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/primary_button.dart';

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

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// 🔥 COMMON PASSWORD
  Future<String> _getDefaultPassword() async {
    final doc = await FirebaseFirestore.instance
        .collection("app_settings")
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

      for (int i = start; i <= end; i++) {
        final roll = i.toString().padLeft(2, '0');
        final id = "es${year}${dept}$roll";

        await FirebaseFirestore.instance.collection("users").doc(id).set({
          "role": "student",
          "active": true,
          "password": password,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bulk students created successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => loading = false);
  }

  /// 🔥 SINGLE STUDENT ADD
  Future<void> _addSingleStudent() async {
    setState(() => loading = true);

    try {
      final year = singleYearController.text.trim();
      final dept = singleDeptController.text.trim().toLowerCase();
      final roll = singleRollController.text.trim().padLeft(2, '0');

      final id = "es${year}${dept}$roll";
      final password = await _getDefaultPassword();

      await FirebaseFirestore.instance.collection("users").doc(id).set({
        "role": "student",
        "active": true,
        "password": password,
        "createdAt": FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Student $id added")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => loading = false);
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
        ],
      ),
    );
  }
}
