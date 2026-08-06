import 'package:esec_bus/core/firebase/firestore_schema.dart';

class BusRecord {
  final String id;
  final Map<String, dynamic> data;

  const BusRecord({required this.id, required this.data});

  Map<String, dynamic> get route => firestoreMap(data['route']);
  Map<String, dynamic> get assignment => firestoreMap(data['assignment']);
  Map<String, dynamic> get tracking => firestoreMap(data['tracking']);
  Map<String, dynamic> get currentPoint =>
      firestoreMap(tracking['currentPoint']);

  String get busNo => firestoreString(data['busNo']) ?? id;
  bool get active => data['active'] == true;

  String get routeNo => firestoreString(route['routeNo']) ?? '';
  String get routeName => firestoreString(route['routeName']) ?? '-';
  String get startPoint => firestoreString(route['startPoint']) ?? '';
  String get endPoint => firestoreString(route['endPoint']) ?? '';
  String get via => firestoreString(route['via']) ?? '';

  String? get assignedDriverId => firestoreString(assignment['driverId']);
  String? get trackingDriverId => firestoreString(tracking['driverId']);

  bool get isTripActive =>
      tracking['isActive'] == true ||
      firestoreString(tracking['status'])?.toLowerCase() == 'running';

  String get trackingStatus {
    return firestoreString(tracking['status'])?.toLowerCase() ??
        (isTripActive ? 'running' : 'stopped');
  }

  double? get latitude => firestoreDouble(currentPoint['latitude']);
  double? get longitude => firestoreDouble(currentPoint['longitude']);
}
