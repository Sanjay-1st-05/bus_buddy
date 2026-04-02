import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:esec_bus/ui/auth/login.dart';
import 'package:esec_bus/ui/admin/add_bus.dart';
import 'package:esec_bus/ui/admin/assign_driver.dart';
import 'package:esec_bus/ui/admin/edit_bus.dart';
import 'package:esec_bus/ui/admin/generate_students.dart';
import 'package:esec_bus/ui/widgets/primary_button.dart';
import '../../services/session.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  void _logout(BuildContext context) {
    Session.role = null;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _deleteBus(BuildContext context, String busId) async {
    await FirebaseFirestore.instance
        .collection("bus_location")
        .doc(busId)
        .delete();
    await FirebaseFirestore.instance
        .collection("bus_master")
        .doc(busId)
        .delete();
    await FirebaseFirestore.instance
        .collection("bus_routes")
        .doc(busId)
        .delete();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Bus deleted successfully")));
  }

  Future<void> _toggleStatus(String busId, bool currentStatus) async {
    await FirebaseFirestore.instance
        .collection("bus_location")
        .doc(busId)
        .update({
          "isActive": !currentStatus,
          "updatedAt": FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    if (Session.role != "admin") {
      return const Scaffold(body: Center(child: Text("Unauthorized Access")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("bus_master")
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final buses = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Manage College Transport",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              /// ✅ FULL WIDTH BUTTONS (LIKE YOUR 2nd IMAGE)
              _fullButton(context, "Add Bus", Icons.add, const AddBusPage()),
              const SizedBox(height: 12),
              _fullButton(
                context,
                "Assign Driver",
                Icons.assignment_ind,
                const AssignDriverPage(),
              ),
              const SizedBox(height: 12),
              _fullButton(
                context,
                "Generate Students",
                Icons.groups,
                const BulkStudentGenerator(),
              ),

              const SizedBox(height: 30),

              const Text(
                "Bus Overview",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (buses.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("No buses available"),
                  ),
                ),

              ...buses.map((doc) {
                final data = doc.data() as Map<String, dynamic>;

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("bus_location")
                      .doc(doc.id)
                      .snapshots(),
                  builder: (context, locationSnap) {
                    final location =
                        locationSnap.data?.data() as Map<String, dynamic>?;

                    final active = location?["isActive"] ?? false;
                    final lat = (location?["latitude"] ?? 0).toDouble();
                    final lng = (location?["longitude"] ?? 0).toDouble();

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.directions_bus),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    data["busNo"] ?? doc.id,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: active,
                                  onChanged: (_) =>
                                      _toggleStatus(doc.id, active),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("${data["routeNo"]} - ${data["routeName"]}"),
                            Text("Via: ${data["via"] ?? "-"}"),
                            Text(
                              "Lat: $lat | Lng: $lng",
                              style: const TextStyle(fontSize: 11),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditBusPage(busId: doc.id),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteBus(context, doc.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// 🔥 FULL WIDTH BUTTON
  Widget _fullButton(
    BuildContext context,
    String text,
    IconData icon,
    Widget page,
  ) {
    return SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        text: text,
        icon: icon,
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        },
      ),
    );
  }
}
