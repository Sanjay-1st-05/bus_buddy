import 'package:esec_bus/shared/models/app_user.dart';
import 'package:esec_bus/shared/models/user_role.dart';

class Session {
  static const String adminRole = "admin";
  static const String driverRole = "driver";
  static const String studentRole = "student";

  static const Set<String> validRoles = {adminRole, driverRole, studentRole};

  static AppUser? currentUser;

  static String? get role => currentUser?.role.value;
  static String? get userId => currentUser?.id;

  static bool get isLoggedIn => currentUser != null;
  static bool get isAdmin => currentUser?.role == UserRole.admin;
  static bool get isDriver => currentUser?.role == UserRole.driver;
  static bool get isStudent => currentUser?.role == UserRole.student;

  static bool hasRole(String expectedRole) => role == expectedRole;

  static bool isValidRole(String? value) {
    return UserRole.fromValue(value) != null;
  }

  static void setUser({required String id, required String userRole}) {
    final parsedRole = UserRole.fromValue(userRole);
    if (parsedRole == null) {
      throw ArgumentError("Invalid user role: $userRole");
    }

    currentUser = AppUser(id: id, role: parsedRole, active: true);
  }

  static void setCurrentUser(AppUser user) {
    currentUser = user;
  }

  static void clear() {
    currentUser = null;
  }
}
