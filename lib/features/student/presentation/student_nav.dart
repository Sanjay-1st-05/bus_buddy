import 'package:esec_bus/features/authentication/presentation/login.dart';
import 'package:flutter/material.dart';

import 'package:esec_bus/features/student/presentation/student_home.dart';
import 'package:esec_bus/core/services/session.dart';
import 'package:esec_bus/core/services/auth_service.dart';
import 'package:esec_bus/features/student/services/student_service.dart';
import 'package:esec_bus/shared/widgets/app_surface.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';

class StudentNav extends StatefulWidget {
  const StudentNav({super.key});

  @override
  State<StudentNav> createState() => _StudentNavState();
}

class _StudentNavState extends State<StudentNav> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    StudentHome(), // Bus list / track
    _ProfilePage(), // Profile only
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    /// 🔥 SESSION NOT SET
    if (!Session.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      });

      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    /// 🔒 WRONG ROLE
    if (!Session.isStudent) {
      return const Scaffold(
        body: Center(
          child: Text("Unauthorized Access", style: TextStyle(fontSize: 16)),
        ),
      );
    }

    /// ✅ STUDENT UI
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: "Track",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------
/// PROFILE PAGE
/// ------------------------------------------------------
class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<StudentProfile?>(
          future: _loadProfile(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = snapshot.data;
            final studentId = profile?.id ?? Session.userId ?? "-";

            return ListView(
              children: [
                AppSurface(
                  child: Row(
                    children: [
                      Container(
                        height: 62,
                        width: 62,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: Theme.of(context).colorScheme.primary,
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentId,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            const StatusBadge(
                              text: "Student",
                              color: Colors.indigo,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _AssignmentCard(profile: profile),
                const SizedBox(height: 16),
                AppSurface(
                  onTap: () async {
                    await AuthService.logout();

                    if (!context.mounted) return;

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 12),
                      Text("Logout"),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<StudentProfile?> _loadProfile() async {
    final studentId = Session.userId;
    if (studentId == null) return null;

    return StudentService.getProfile(studentId);
  }
}

class _AssignmentCard extends StatelessWidget {
  final StudentProfile? profile;

  const _AssignmentCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final assignedBusId = profile?.assignedBusId;
    final routeNo = profile?.routeNo;
    final routeName = profile?.routeName;

    return AppSurface(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bus_filled_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Bus Assignment",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  assignedBusId == null
                      ? Icons.info_outline
                      : Icons.check_circle,
                  color: assignedBusId == null ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ProfileRow(
              label: "Status",
              value: assignedBusId == null ? "Not assigned" : "Assigned",
            ),
            _ProfileRow(label: "Bus ID", value: assignedBusId ?? "-"),
            _ProfileRow(label: "Route No", value: routeNo ?? "-"),
            _ProfileRow(label: "Route Name", value: routeName ?? "-"),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
