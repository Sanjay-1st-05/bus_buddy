import 'package:esec_bus/features/authentication/presentation/login.dart';
import 'package:flutter/material.dart';
import 'package:esec_bus/features/admin/presentation/admin_home.dart';
import 'package:esec_bus/features/driver/presentation/driver_home.dart';
import 'package:esec_bus/shared/models/user_role.dart';
import 'package:esec_bus/features/student/presentation/student_nav.dart';
import 'package:esec_bus/core/services/session.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔥 FIRST TIME / LOGOUT
    if (!Session.isLoggedIn) {
      return const LoginPage();
    }

    // 🔥 ROLE-BASED ENTRY
    switch (Session.currentUser?.role) {
      case UserRole.admin:
        return const AdminHome();
      case UserRole.driver:
        return const DriverHome();
      case UserRole.student:
        return const StudentNav();
      default:
        return const LoginPage();
    }
  }
}
