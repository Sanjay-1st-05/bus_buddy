import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_track_page.dart';

class StudentHome extends StatelessWidget {
  const StudentHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Available Buses"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("bus_master")
            .where("active", isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_bus, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    "No active buses available",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final buses = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: buses.length,
            itemBuilder: (context, index) {
              final bus = buses[index];
              final data = bus.data() as Map<String, dynamic>;

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.indigo.shade100,
                    child: const Icon(
                      Icons.directions_bus,
                      color: Colors.indigo,
                    ),
                  ),
                  title: Text(
                    data["busNo"] ?? bus.id,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        "${data["routeNo"] ?? ""} - ${data["routeName"] ?? ""}",
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Tap to Track Live",
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentTrackPage(busId: bus.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
