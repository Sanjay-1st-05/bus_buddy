class FirestoreCollections {
  static const String buses = 'buses';
  static const String users = 'users';
  static const String admins = 'admins';
  static const String drivers = 'drivers';
  static const String students = 'students';
  static const String appSettings = 'app_settings';
  static const String routes = 'routes';
  static const String tracking = 'tracking';
  static const String trips = 'trips';
  static const String smartSyncRuntime = 'smartsync_runtime';
  static const String emergencies = 'emergencies';

  const FirestoreCollections._();
}

class FirestoreSchemaVersions {
  static const int consolidated = 3;

  const FirestoreSchemaVersions._();
}

Map<String, dynamic> firestoreMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const <String, dynamic>{};
}

String? firestoreString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return value.trim();
}

double? firestoreDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  return null;
}
