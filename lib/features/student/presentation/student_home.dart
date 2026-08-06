import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:esec_bus/core/services/session.dart';
import 'package:esec_bus/features/student/services/student_service.dart';
import 'package:esec_bus/shared/models/bus_record.dart';
import 'package:esec_bus/shared/widgets/app_page_header.dart';
import 'package:esec_bus/shared/widgets/app_surface.dart';
import 'package:esec_bus/shared/widgets/empty_state.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';
import 'package:esec_bus/features/tracking/presentation/student_track_page.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late final Future<StudentProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    final studentId = Session.userId;
    _profileFuture = studentId == null
        ? Future<StudentProfile?>.value(null)
        : StudentService.getProfile(studentId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Track Bus")),
      body: FutureBuilder<StudentProfile?>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = profileSnapshot.data;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: StudentService.activeBusesStream(),
            builder: (context, busSnapshot) {
              if (busSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!busSnapshot.hasData || busSnapshot.data!.docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.directions_bus_outlined,
                  title: "No active buses",
                  message: "Live buses will appear here once a trip starts.",
                );
              }

              final buses = _prioritizeAssignedBus(
                busSnapshot.data!.docs,
                profile?.assignedBusId,
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  AppPageHeader(
                    title: "Live Tracking",
                    subtitle: profile?.assignedBusId == null
                        ? "Choose an active bus to view its current trip."
                        : "Your assigned bus is prioritized at the top.",
                    icon: Icons.location_on_outlined,
                    trailing: [
                      StatusBadge(
                        text: "${buses.length} active",
                        color: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _StudentBusHeader(profile: profile),
                  const SizedBox(height: 16),
                  ...buses.map((bus) {
                    final isAssigned = profile?.assignedBusId == bus.id;

                    return _BusCard(
                      busId: bus.id,
                      data: bus.data(),
                      isAssigned: isAssigned,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentTrackPage(busId: bus.id),
                          ),
                        );
                      },
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _prioritizeAssignedBus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> buses,
    String? assignedBusId,
  ) {
    if (assignedBusId == null) return buses;

    final sorted = [...buses];
    sorted.sort((a, b) {
      if (a.id == assignedBusId) return -1;
      if (b.id == assignedBusId) return 1;
      return 0;
    });

    return sorted;
  }
}

class _StudentBusHeader extends StatelessWidget {
  final StudentProfile? profile;

  const _StudentBusHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final assignedBusId = profile?.assignedBusId;

    return AppSurface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            assignedBusId == null
                ? Icons.info_outline
                : Icons.verified_outlined,
            color: assignedBusId == null ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your Bus",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  assignedBusId == null
                      ? "No assigned bus found. Showing all active buses."
                      : "Assigned bus: $assignedBusId",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusCard extends StatelessWidget {
  final String busId;
  final Map<String, dynamic> data;
  final bool isAssigned;
  final VoidCallback onTap;

  const _BusCard({
    required this.busId,
    required this.data,
    required this.isAssigned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bus = BusRecord(id: busId, data: data);
    final busNo = bus.busNo;
    final routeNo = bus.routeNo;
    final routeName = bus.routeName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: isAssigned
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.directions_bus_filled_outlined,
                color: isAssigned
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          busNo,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (isAssigned)
                        const StatusBadge(
                          text: "Assigned",
                          color: Colors.indigo,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$routeNo - $routeName",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    isAssigned
                        ? "Track your assigned bus"
                        : "View live tracking",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
