import 'package:esec_bus/ui/auth/login.dart';
import 'package:flutter/material.dart';
import 'package:esec_bus/ui/admin/admin_home.dart';
import 'package:esec_bus/ui/driver/driver_home.dart';
import 'student/student_nav.dart';
import '../services/session.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔥 FIRST TIME / LOGOUT
    if (Session.role == null) {
      return const LoginPage();
    }

    // 🔥 ROLE-BASED ENTRY
    switch (Session.role) {
      case "admin":
        return const AdminHome();
      case "driver":
        return const DriverHome();
      case "student":
        return const StudentNav();
      default:
        return const LoginPage();
    }
  }
}
