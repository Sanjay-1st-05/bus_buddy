import 'package:esec_bus/ui/auth/login.dart';
import 'package:flutter/material.dart';

import 'student_home.dart';
import '../../services/session.dart';

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
    if (Session.role == null) {
      Future.microtask(() {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      });

      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    /// 🔒 WRONG ROLE
    if (Session.role != "student") {
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
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
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
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: 16),

            const Text(
              "Student",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 24),

            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Logout"),
              onTap: () {
                Session.role = null;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
