import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/core/services/session.dart';
import 'package:esec_bus/features/tracking/presentation/student_track_page.dart';
import 'package:esec_bus/shared/widgets/app_surface.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';

class AdminOperationalAlerts extends StatefulWidget {
  const AdminOperationalAlerts({super.key});

  @override
  State<AdminOperationalAlerts> createState() => _AdminOperationalAlertsState();
}

class _AdminOperationalAlertsState extends State<AdminOperationalAlerts> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final Set<String> _presentedAlerts = <String>{};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseFirestore.instance
        .collection(FirestoreCollections.emergencies)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(_handleAlerts);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleAlerts(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted) return;
    final alerts = snapshot.docs
        .where((doc) {
          final status = doc.data()['status']?.toString().toLowerCase();
          return status == 'active' || status == 'acknowledged';
        })
        .toList(growable: false);

    setState(() => _alerts = alerts);

    for (final alert in alerts.reversed) {
      final data = alert.data();
      if (data['status']?.toString().toLowerCase() != 'active' ||
          data['acknowledged'] == true ||
          !_presentedAlerts.add(alert.id)) {
        continue;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showAlertDialog(alert));
      });
    }
  }

  Future<void> _showAlertDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> alert,
  ) async {
    await SystemSound.play(SystemSoundType.alert);
    final data = alert.data();
    final details = await _loadBusDetails(data['busId']?.toString());
    if (!mounted) return;

    final isSos = data['type']?.toString() == 'sos';
    final title = isSos ? 'EMERGENCY ALERT' : 'TRACKING LOST';
    final color = isSos ? Colors.red : Colors.orange;
    final busId = data['busId']?.toString() ?? 'Unknown';
    final location = _map(data['location']);
    final latitude = _double(location['latitude']);
    final longitude = _double(location['longitude']);
    final lastSignal = _dateTime(
      data['lastSignalAt'] ?? location['capturedAt'] ?? data['createdAt'],
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          isSos ? Icons.sos_rounded : Icons.gps_off_rounded,
          color: color,
          size: 38,
        ),
        title: Text(title, style: TextStyle(color: color)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlertLine('Bus', details.busNo ?? busId),
              _AlertLine(
                'Driver',
                data['driverId']?.toString() ?? 'Unassigned',
              ),
              _AlertLine('Route', details.routeName ?? 'Not available'),
              if (details.faculty != null)
                _AlertLine('Assigned Faculty', details.faculty!),
              if (details.driverMobile != null)
                _AlertLine('Driver Contact', details.driverMobile!),
              _AlertLine('Last update', _formatTime(lastSignal)),
              if (latitude != null && longitude != null)
                _AlertLine(
                  'GPS',
                  '${latitude.toStringAsFixed(5)}, '
                      '${longitude.toStringAsFixed(5)}',
                ),
              const SizedBox(height: 10),
              Text(
                isSos
                    ? 'Emergency reported. Immediately contact the driver '
                          'and the assigned bus in-charge.'
                    : 'The active trip stopped sending driver phone GPS. '
                          'Check the driver device and last known location.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _acknowledge(alert.reference);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Acknowledge'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentTrackPage(busId: busId),
                ),
              );
            },
            child: const Text('Open Live Tracking'),
          ),
        ],
      ),
    );
  }

  Future<_BusAlertDetails> _loadBusDetails(String? busId) async {
    if (busId == null || busId.isEmpty) return const _BusAlertDetails();
    try {
      final bus = await FirebaseFirestore.instance
          .collection(FirestoreCollections.buses)
          .doc(busId)
          .get();
      final data = bus.data() ?? const <String, dynamic>{};
      final route = _map(data['route']);
      final assignment = _map(data['assignment']);
      final profile = _map(data['profile']);
      final driverId = assignment['driverId']?.toString();
      String? mobile;
      if (driverId != null && driverId.isNotEmpty) {
        final driver = await FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(driverId)
            .get();
        final driverProfile = _map(driver.data()?['profile']);
        mobile =
            driverProfile['mobile']?.toString() ??
            driverProfile['mobileNo']?.toString();
      }
      return _BusAlertDetails(
        busNo: data['busNo']?.toString(),
        routeName: route['routeName']?.toString() ?? route['name']?.toString(),
        faculty:
            assignment['facultyName']?.toString() ??
            profile['facultyName']?.toString(),
        driverMobile: mobile,
      );
    } catch (_) {
      return const _BusAlertDetails();
    }
  }

  Future<void> _acknowledge(DocumentReference<Map<String, dynamic>> reference) {
    return reference.update({
      'status': 'acknowledged',
      'acknowledged': true,
      'acknowledgedBy': Session.userId,
      'acknowledgedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _clear(DocumentReference<Map<String, dynamic>> reference) {
    return reference.update({
      'status': 'cleared',
      'cleared': true,
      'clearedBy': Session.userId,
      'clearedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty) return const SizedBox.shrink();

    final activeCount = _alerts
        .where((alert) => alert.data()['status'] == 'active')
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Operational Alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  text: '$activeCount unread',
                  color: activeCount == 0 ? Colors.blueGrey : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final alert in _alerts.take(6)) _buildAlertRow(context, alert),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertRow(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> alert,
  ) {
    final data = alert.data();
    final isSos = data['type'] == 'sos';
    final active = data['status'] == 'active';
    final color = isSos ? Colors.red : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(
            isSos ? Icons.sos_rounded : Icons.gps_off_rounded,
            color: color,
          ),
          title: Text(
            '${isSos ? 'Emergency' : 'Tracking lost'} · '
            '${data['busId'] ?? 'Unknown bus'}',
          ),
          subtitle: Text(
            '${data['driverId'] ?? 'Unassigned driver'} · '
            '${_formatTime(_dateTime(data['createdAt']))}',
          ),
          trailing: active
              ? TextButton(
                  onPressed: () => _acknowledge(alert.reference),
                  child: const Text('ACK'),
                )
              : IconButton(
                  tooltip: 'Clear alert',
                  onPressed: () => _clear(alert.reference),
                  icon: const Icon(Icons.check_circle_outline),
                ),
          onTap: () => _showAlertDialog(alert),
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static DateTime? _dateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _formatTime(DateTime? value) {
    if (value == null) return 'Time unavailable';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _AlertLine extends StatelessWidget {
  final String label;
  final String value;

  const _AlertLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _BusAlertDetails {
  final String? busNo;
  final String? routeName;
  final String? faculty;
  final String? driverMobile;

  const _BusAlertDetails({
    this.busNo,
    this.routeName,
    this.faculty,
    this.driverMobile,
  });
}
