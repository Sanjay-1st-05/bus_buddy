import 'package:esec_bus/core/firebase/firestore_schema.dart';

import 'user_role.dart';

class AppUser {
  final String id;
  final UserRole role;
  final bool active;
  final Map<String, dynamic> data;

  const AppUser({
    required this.id,
    required this.role,
    required this.active,
    this.data = const {},
  });

  factory AppUser.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final roleValue = data["role"];
    final role = roleValue is String ? UserRole.fromValue(roleValue) : null;

    if (role == null) {
      throw const FormatException("Invalid account role");
    }

    return AppUser(
      id: id,
      role: role,
      active: data["active"] == true,
      data: Map.unmodifiable(data),
    );
  }

  Map<String, dynamic> get profile => firestoreMap(data["profile"]);
  Map<String, dynamic> get assignment => firestoreMap(data["assignment"]);

  String? get displayName => firestoreString(profile["name"]);
  String? get mobile => firestoreString(profile["mobile"]);
  String? get assignedBusId => firestoreString(assignment["busId"]);
}
