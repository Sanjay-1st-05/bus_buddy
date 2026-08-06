import 'package:cloud_functions/cloud_functions.dart';

class ProvisionedUser {
  final String userId;
  final String role;

  const ProvisionedUser({required this.userId, required this.role});
}

class UserProvisioningService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );

  static Future<ProvisionedUser> provision({
    required String userId,
    required String password,
    required String role,
    Map<String, Object?> profile = const {},
    Map<String, Object?> assignment = const {},
  }) async {
    final result = await _functions.httpsCallable('provisionUser').call({
      'userId': userId,
      'password': password,
      'role': role,
      'profile': profile,
      if (assignment.isNotEmpty) 'assignment': assignment,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return ProvisionedUser(
      userId: data['userId'] as String,
      role: data['role'] as String,
    );
  }

  static Future<int> provisionMany(List<Map<String, Object?>> users) async {
    final result = await _functions.httpsCallable('provisionUsers').call({
      'users': users,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['created'] as int? ?? 0;
  }
}
