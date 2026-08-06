import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esec_bus/core/firebase/firestore_schema.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_controller.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_event.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_state.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_value_source.dart';
import 'package:esec_bus/smartsync/debug/smartsync_developer_dashboard.dart';
import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:flutter/material.dart';

class SmartSyncDeveloperPreviewPage extends StatefulWidget {
  const SmartSyncDeveloperPreviewPage({super.key});

  @override
  State<SmartSyncDeveloperPreviewPage> createState() =>
      _SmartSyncDeveloperPreviewPageState();
}

class _SmartSyncDeveloperPreviewPageState
    extends State<SmartSyncDeveloperPreviewPage> {
  late final SmartSyncDebugController _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  @override
  void initState() {
    super.initState();
    _controller = SmartSyncDebugController();
    _subscription = FirebaseFirestore.instance
        .collection(FirestoreCollections.smartSyncRuntime)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen(_handleSnapshot, onError: _handleError);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SmartSyncDeveloperDashboard(controller: _controller);
  }

  void _handleSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) {
      _controller.addEvent(
        'Waiting for an active driver ByZra runtime',
        level: SmartSyncDebugEventLevel.warning,
      );
      return;
    }

    final data = snapshot.docs.first.data();
    final now = _dateTime(data['updatedAt']) ?? DateTime.now();
    final events = _events(data['recentEvents']);
    final sources = <String, SmartSyncDebugValueSource>{
      'networkQuality': _source(data, 'networkQuality'),
      'latency': _source(data, 'latencyMs'),
      'packetLoss': _source(data, 'packetLossPercent'),
      'signalStability': _source(data, 'signalStability'),
      'syncInterval': _source(data, 'syncIntervalSeconds'),
      'engineDecision': _source(data, 'decision'),
      'retryCount': _source(data, 'retryCount'),
      'offlineQueueSize': _source(data, 'offlineQueueSize'),
      'gpsAccuracy': _source(data, 'gpsAccuracyMeters'),
      'movementStatus': _source(data, 'movementStatus'),
      'batteryMode': data['batteryReadingAvailable'] == true
          ? SmartSyncDebugValueSource.live
          : SmartSyncDebugValueSource.fallback,
      'activeModules': _source(data, 'activeModules'),
      'routeStatus': _source(data, 'routeStatus'),
      'geofenceStatus': _source(data, 'geofenceEvents'),
      'healthScore': _source(data, 'healthScore'),
    };

    _controller.update(
      SmartSyncDebugState(
        networkStatus: NetworkStatus(
          quality: _networkQuality(data['networkQuality']),
          latency: Duration(milliseconds: _integer(data['latencyMs'])),
          packetLossPercent: _double(data['packetLossPercent']),
          signalStability: _double(data['signalStability']),
          measuredAt: now,
        ),
        synchronizationInterval: Duration(
          seconds: _integer(data['syncIntervalSeconds']),
        ),
        engineDecision: SyncDecision(
          action: _syncAction(data['decision']),
          reason: data['decisionReason']?.toString() ?? 'runtime',
        ),
        retryCount: _integer(data['retryCount']),
        offlineQueueSize: _integer(data['offlineQueueSize']),
        gpsAccuracyMeters: _nullableDouble(data['gpsAccuracyMeters']),
        movementState: MovementState(
          type: _movementType(data['movementStatus']),
          distanceSinceLastSyncMeters: 0,
        ),
        batteryState: BatteryState(
          levelPercent: _integer(data['batteryLevel']),
          isCharging: false,
          mode: _batteryMode(data['batteryMode']),
        ),
        activeModules: _strings(data['activeModules']),
        routeStatus: data['routeStatus']?.toString() ?? 'unavailable',
        geofenceStatus: _strings(data['geofenceEvents']).join(', '),
        healthScore: _integer(data['healthScore']),
        runtimeMetrics: _map(data['runtimeMetrics']),
        moduleRuntime: _map(data['modules']),
        runtimeSamples: _maps(data['runtimeSamples']),
        recentEvents: events,
        valueSources: sources,
        updatedAt: now,
      ),
    );
  }

  void _handleError(Object error) {
    _controller.addEvent(
      'Runtime telemetry unavailable: $error',
      level: SmartSyncDebugEventLevel.error,
    );
  }

  List<SmartSyncDebugEvent> _events(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final data = Map<String, dynamic>.from(raw);
          return SmartSyncDebugEvent(
            message:
                '${data['name'] ?? 'runtime_event'}: ${data['reason'] ?? ''}',
            level: SmartSyncDebugEventLevel.info,
            occurredAt:
                DateTime.tryParse(data['recordedAt']?.toString() ?? '') ??
                DateTime.now(),
          );
        })
        .toList(growable: false);
  }

  NetworkQuality _networkQuality(Object? value) =>
      NetworkQuality.values.where((item) => item.name == value).firstOrNull ??
      NetworkQuality.offline;

  MovementType _movementType(Object? value) =>
      MovementType.values.where((item) => item.name == value).firstOrNull ??
      MovementType.stopped;

  BatteryMode _batteryMode(Object? value) =>
      BatteryMode.values.where((item) => item.name == value).firstOrNull ??
      BatteryMode.normal;

  SyncAction _syncAction(Object? value) =>
      SyncAction.values.where((item) => item.name == value).firstOrNull ??
      SyncAction.wait;

  int _integer(Object? value) => value is num ? value.toInt() : 0;
  double _double(Object? value) => value is num ? value.toDouble() : 0;
  double? _nullableDouble(Object? value) =>
      value is num ? value.toDouble() : null;
  List<String> _strings(Object? value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];
  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
      : const [];
  DateTime? _dateTime(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  SmartSyncDebugValueSource _source(Map<String, dynamic> data, String field) =>
      data.containsKey(field) && data[field] != null
      ? SmartSyncDebugValueSource.live
      : SmartSyncDebugValueSource.fallback;
}
