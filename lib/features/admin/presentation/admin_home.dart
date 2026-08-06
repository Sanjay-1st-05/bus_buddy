import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/features/authentication/presentation/login.dart';
import 'package:esec_bus/features/admin/presentation/add_bus.dart';
import 'package:esec_bus/features/admin/presentation/admin_operational_alerts.dart';
import 'package:esec_bus/features/admin/presentation/assign_driver.dart';
import 'package:esec_bus/features/admin/presentation/edit_bus.dart';
import 'package:esec_bus/features/admin/presentation/generate_students.dart';
import 'package:esec_bus/shared/widgets/app_action_tile.dart';
import 'package:esec_bus/shared/widgets/app_metric_tile.dart';
import 'package:esec_bus/shared/widgets/app_page_header.dart';
import 'package:esec_bus/shared/widgets/app_surface.dart';
import 'package:esec_bus/shared/widgets/empty_state.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';
import 'package:esec_bus/shared/models/bus_record.dart';
import 'package:esec_bus/core/services/session.dart';
import 'package:esec_bus/core/services/auth_service.dart';
import 'package:esec_bus/features/tracking/services/tracking_presence.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _deleteBus(BuildContext context, String busId) async {
    final confirmed = await _confirmDelete(context, busId);
    if (!confirmed) return;

    final firestore = FirebaseFirestore.instance;
    final busRef = firestore.collection(FirestoreCollections.buses).doc(busId);
    final busDoc = await busRef.get();
    final busData = busDoc.data();

    if (!busDoc.exists || busData == null) {
      if (context.mounted) {
        _showMessage(context, "Bus not found");
      }
      return;
    }

    final bus = BusRecord(id: busId, data: busData);

    if (!context.mounted) return;

    if (bus.isTripActive) {
      _showMessage(context, "Stop the running trip before deleting this bus");
      return;
    }

    final assignedUsers = await firestore
        .collection(FirestoreCollections.users)
        .where("assignment.busId", isEqualTo: busId)
        .get();

    final batch = firestore.batch();
    batch.delete(busRef);

    for (final user in assignedUsers.docs) {
      batch.update(user.reference, {
        "assignment": FieldValue.delete(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Bus deleted successfully")));
  }

  Future<void> _stopTrip(String busId) async {
    await FirebaseFirestore.instance
        .collection(FirestoreCollections.buses)
        .doc(busId)
        .update({
          "tracking.isActive": false,
          "tracking.status": "stopped",
          "tracking.serviceHeartbeatAt": FieldValue.delete(),
          "tracking.lastUpdatedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
  }

  Future<bool> _confirmDelete(BuildContext context, String busId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Bus"),
          content: Text(
            "Delete $busId? This will remove the bus, route, live location, and clear related assignments.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!Session.isAdmin) {
      return const Scaffold(body: Center(child: Text("Unauthorized Access")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _logout(context);
            },
          ),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(FirestoreCollections.buses)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final buses = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AppPageHeader(
                title: "Transport Control",
                subtitle:
                    "Manage buses, driver assignments, student access, and ByZra diagnostics.",
                icon: Icons.admin_panel_settings_outlined,
                trailing: [
                  StatusBadge(
                    text: "${buses.length} buses",
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const AdminOperationalAlerts(),
              Row(
                children: [
                  Expanded(
                    child: AppMetricTile(
                      label: "Fleet",
                      value: "${buses.length}",
                      icon: Icons.directions_bus_filled_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppMetricTile(
                      label: "Operations",
                      value: kDebugMode ? "4" : "3",
                      icon: Icons.tune_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppActionTile(
                title: "Add Bus",
                subtitle: "Register a bus, route, and driver profile.",
                icon: Icons.add_road_outlined,
                onTap: () => _open(context, const AddBusPage()),
              ),
              const SizedBox(height: 10),
              AppActionTile(
                title: "Assign Driver",
                subtitle: "Connect active drivers to available buses.",
                icon: Icons.assignment_ind_outlined,
                color: Colors.teal,
                onTap: () => _open(context, const AssignDriverPage()),
              ),
              const SizedBox(height: 10),
              AppActionTile(
                title: "Generate Students",
                subtitle: "Create student accounts for assigned routes.",
                icon: Icons.groups_2_outlined,
                color: Colors.deepPurple,
                onTap: () => _open(context, const BulkStudentGenerator()),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 10),
                AppActionTile(
                  title: "ByZra Debug",
                  subtitle: "Inspect live engine and network runtime state.",
                  icon: Icons.bug_report_outlined,
                  color: Colors.orange,
                  onTap: () =>
                      _open(context, const SmartSyncDeveloperPreviewPage()),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                "Bus Overview",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              if (buses.isEmpty)
                const EmptyState(
                  icon: Icons.directions_bus_outlined,
                  title: "No buses available",
                  message: "Add the first bus to start managing live tracking.",
                ),

              ...buses.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final bus = BusRecord(id: doc.id, data: data);
                final tracking = bus.tracking;
                final currentPoint = bus.currentPoint;
                final route = bus.route;
                final status = _trackingStatus(tracking);
                final statusColor = _trackingStatusColor(status);
                final storedStatus = _readString(
                  tracking["status"],
                )?.toLowerCase();
                final isTripActive =
                    tracking["isActive"] == true || storedStatus == "running";
                final driverId = bus.assignedDriverId ?? bus.trackingDriverId;
                final lat = bus.latitude;
                final lng = bus.longitude;
                final hasValidLocation = _hasValidLocation(lat, lng);
                final lastUpdatedAt =
                    _readTimestamp(tracking["serviceHeartbeatAt"]) ??
                    _readTimestamp(currentPoint["capturedAt"]) ??
                    _readTimestamp(tracking["lastUpdatedAt"]) ??
                    _readTimestamp(data["updatedAt"]);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              height: 42,
                              width: 42,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.directions_bus_filled_outlined,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                bus.busNo,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Switch(
                              value: isTripActive,
                              onChanged: (enabled) {
                                if (enabled) {
                                  _showMessage(
                                    context,
                                    "Only the assigned driver can start this trip",
                                  );
                                  return;
                                }
                                _stopTrip(doc.id);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "${bus.routeNo} - ${bus.routeName}",
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          "Via ${firestoreString(route["via"]) ?? "-"}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusBadge(text: status, color: statusColor),
                            if (driverId != null)
                              StatusBadge(
                                text: "Driver: $driverId",
                                color: Colors.indigo,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Last update: ${_lastUpdatedText(lastUpdatedAt)}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasValidLocation
                              ? "Lat: ${lat!.toStringAsFixed(5)} | Lng: ${lng!.toStringAsFixed(5)}"
                              : "Location: Waiting for valid GPS update",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EditBusPage(busId: doc.id),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteBus(context, doc.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  String _trackingStatus(Map<String, dynamic>? location) {
    if (location == null) return "Not Ready";

    final status = _readString(location["status"])?.toLowerCase();
    final isActive = location["isActive"] == true || status == "running";
    final currentPoint = firestoreMap(location["currentPoint"]);
    final lat = _readDouble(currentPoint["latitude"]);
    final lng = _readDouble(currentPoint["longitude"]);
    final presence = TrackingPresence.evaluate(
      isActive: isActive,
      hasValidLocation: _hasValidLocation(lat, lng),
      coordinateCapturedAt: _readTimestamp(currentPoint["capturedAt"]),
      serviceHeartbeatAt: _readTimestamp(location["serviceHeartbeatAt"]),
      speedMetersPerSecond: _readDouble(currentPoint["speed"]),
    );

    switch (presence.status) {
      case TrackingPresenceStatus.stopped:
        return "Stopped";
      case TrackingPresenceStatus.startingGps:
        return "Starting GPS";
      case TrackingPresenceStatus.live:
        return "Running";
      case TrackingPresenceStatus.stationary:
        return "Stationary";
      case TrackingPresenceStatus.delayed:
        return "Disconnected";
    }
  }

  Color _trackingStatusColor(String status) {
    switch (status) {
      case "Running":
        return Colors.green;
      case "Stationary":
        return Colors.teal;
      case "Stopped":
        return Colors.red;
      case "Disconnected":
        return Colors.orange;
      case "Starting GPS":
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  String _lastUpdatedText(DateTime? lastUpdatedAt) {
    if (lastUpdatedAt == null) return "Not updated yet";

    final difference = DateTime.now().difference(lastUpdatedAt);
    if (difference.inSeconds < 30) return "Live now";
    if (difference.inMinutes < 1) return "Updated under 1 min ago";
    if (difference.inMinutes < 60) {
      return "Updated ${difference.inMinutes} min ago";
    }

    return "Updated ${difference.inHours} hr ago";
  }

  bool _hasValidLocation(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0.0 && lng == 0.0) return false;

    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String? _readString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}
