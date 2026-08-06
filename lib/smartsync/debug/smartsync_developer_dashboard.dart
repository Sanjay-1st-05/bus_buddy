import 'package:esec_bus/smartsync/debug/smartsync_debug_controller.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_event.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_state.dart';
import 'package:esec_bus/smartsync/debug/smartsync_debug_value_source.dart';
import 'package:esec_bus/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class SmartSyncDeveloperDashboard extends StatelessWidget {
  final SmartSyncDebugController controller;

  const SmartSyncDeveloperDashboard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SmartSyncDebugState>(
      stream: controller.stream,
      initialData: controller.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? controller.currentState;

        return Scaffold(
          appBar: AppBar(
            title: const Text('ByZra Developer Dashboard'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          backgroundColor: const Color(0xFFF4F6F8),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SourceLegend(),
              const SizedBox(height: 8),
              Text(
                'Last runtime update: ${_formatTimestamp(state.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Network',
                children: [
                  _MetricTile(
                    label: 'Current Network Quality',
                    value: _titleCase(state.networkStatus.quality.name),
                    source: state.sourceFor('networkQuality'),
                  ),
                  _MetricTile(
                    label: 'Latency',
                    value: '${state.networkStatus.latency.inMilliseconds} ms',
                    source: state.sourceFor('latency'),
                  ),
                  _MetricTile(
                    label: 'Packet Loss',
                    value:
                        '${state.networkStatus.packetLossPercent.toStringAsFixed(1)}%',
                    source: state.sourceFor('packetLoss'),
                  ),
                  _MetricTile(
                    label: 'Signal Stability',
                    value:
                        '${(state.networkStatus.signalStability * 100).toStringAsFixed(0)}%',
                    source: state.sourceFor('signalStability'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Decision',
                children: [
                  _MetricTile(
                    label: 'Current Synchronization Interval',
                    value: _formatDuration(state.synchronizationInterval),
                    source: state.sourceFor('syncInterval'),
                  ),
                  _MetricTile(
                    label: 'Current Engine Decision',
                    value: _titleCase(state.engineDecision.action.name),
                    detail: state.engineDecision.reason,
                    source: state.sourceFor('engineDecision'),
                  ),
                  _MetricTile(
                    label: 'Retry Count',
                    value: state.retryCount.toString(),
                    source: state.sourceFor('retryCount'),
                  ),
                  _MetricTile(
                    label: 'Offline Queue Size',
                    value: state.offlineQueueSize.toString(),
                    source: state.sourceFor('offlineQueueSize'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Vehicle State',
                children: [
                  _MetricTile(
                    label: 'GPS Accuracy',
                    value: state.gpsAccuracyMeters == null
                        ? 'Unknown'
                        : '${state.gpsAccuracyMeters!.toStringAsFixed(1)} m',
                    source: state.sourceFor('gpsAccuracy'),
                  ),
                  _MetricTile(
                    label: 'Movement Status',
                    value: _titleCase(state.movementState.type.name),
                    detail:
                        '${state.movementState.distanceSinceLastSyncMeters.toStringAsFixed(1)} m since last sync',
                    source: state.sourceFor('movementStatus'),
                  ),
                  _MetricTile(
                    label: 'Battery Mode',
                    value: _titleCase(state.batteryState.mode.name),
                    detail:
                        '${state.batteryState.levelPercent}%${state.batteryState.isCharging ? ' charging' : ''}',
                    source: state.sourceFor('batteryMode'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Active Modules',
                children: [
                  if (state.activeModules.isEmpty)
                    const _EmptyMessage('No modules are active yet.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final module in state.activeModules)
                          Chip(
                            label: Text(module),
                            side: BorderSide(color: Colors.grey.shade300),
                            backgroundColor: Colors.white,
                          ),
                        _SourceChip(source: state.sourceFor('activeModules')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Recent Engine Events',
                children: [
                  if (state.recentEvents.isEmpty)
                    const _EmptyMessage('No engine events recorded yet.')
                  else
                    for (final event in state.recentEvents)
                      _EventTile(event: event),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Route and Health',
                children: [
                  _MetricTile(
                    label: 'Route Status',
                    value: _titleCase(state.routeStatus),
                    source: state.sourceFor('routeStatus'),
                  ),
                  _MetricTile(
                    label: 'Geofence Status',
                    value: _titleCase(state.geofenceStatus),
                    source: state.sourceFor('geofenceStatus'),
                  ),
                  _MetricTile(
                    label: 'Health Score',
                    value: '${state.healthScore}/100',
                    source: state.sourceFor('healthScore'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Runtime Module Health',
                children: [
                  if (state.moduleRuntime.isEmpty)
                    const _EmptyMessage(
                      'Waiting for module execution telemetry.',
                    )
                  else
                    for (final entry in state.moduleRuntime.entries)
                      _ModuleRuntimeTile(
                        name: entry.key,
                        data: _map(entry.value),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Packet Optimization',
                children: [
                  _MetricTile(
                    label: 'Original Packet Size',
                    value:
                        '${_number(state.runtimeMetrics['packetOriginalBytes']).toStringAsFixed(0)} B',
                    source: state.sourceFor('activeModules'),
                  ),
                  _MetricTile(
                    label: 'Compressed Packet Size',
                    value:
                        '${_number(state.runtimeMetrics['packetCompressedBytes']).toStringAsFixed(0)} B',
                    source: state.sourceFor('activeModules'),
                  ),
                  _MetricTile(
                    label: 'Compression',
                    value:
                        '${_number(state.runtimeMetrics['compressionPercent']).toStringAsFixed(1)}%',
                    detail:
                        '${_number(state.runtimeMetrics['savedBandwidthBytes']).toStringAsFixed(0)} bytes saved',
                    source: state.sourceFor('activeModules'),
                  ),
                  _MetricTile(
                    label: 'Delivery',
                    value:
                        '${_integer(state.runtimeMetrics['packetsSent'])} sent',
                    detail:
                        '${_integer(state.runtimeMetrics['packetsDropped'])} dropped · '
                        '${_integer(state.runtimeMetrics['actualSyncTimeMs'])} ms last write',
                    source: state.sourceFor('activeModules'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Real Runtime Graphs',
                children: [
                  _RuntimeGraph(
                    title: 'Battery Trend',
                    keyName: 'batteryLevel',
                    unit: '%',
                    samples: state.runtimeSamples,
                    color: Colors.green,
                  ),
                  _RuntimeGraph(
                    title: 'Network Latency',
                    keyName: 'latencyMs',
                    unit: ' ms',
                    samples: state.runtimeSamples,
                    color: Colors.blue,
                  ),
                  _RuntimeGraph(
                    title: 'Signal Stability',
                    keyName: 'signalStability',
                    unit: '',
                    scale: 100,
                    samples: state.runtimeSamples,
                    color: Colors.cyan,
                  ),
                  _RuntimeGraph(
                    title: 'GPS Accuracy',
                    keyName: 'gpsAccuracyMeters',
                    unit: ' m',
                    samples: state.runtimeSamples,
                    color: Colors.deepOrange,
                  ),
                  _RuntimeGraph(
                    title: 'Synchronization Interval',
                    keyName: 'syncIntervalSeconds',
                    unit: ' sec',
                    samples: state.runtimeSamples,
                    color: Colors.indigo,
                  ),
                  _RuntimeGraph(
                    title: 'Movement Speed',
                    keyName: 'speedMetersPerSecond',
                    unit: ' m/s',
                    samples: state.runtimeSamples,
                    color: Colors.teal,
                  ),
                  _RuntimeGraph(
                    title: 'Runtime Health',
                    keyName: 'healthScore',
                    unit: '/100',
                    samples: state.runtimeSamples,
                    color: Colors.purple,
                  ),
                  _RuntimeGraph(
                    title: 'Prediction Confidence',
                    keyName: 'predictionConfidence',
                    unit: '%',
                    scale: 100,
                    samples: state.runtimeSamples,
                    color: Colors.pink,
                  ),
                  _RuntimeGraph(
                    title: 'Retry Count',
                    keyName: 'retryCount',
                    unit: '',
                    samples: state.runtimeSamples,
                    color: Colors.red,
                  ),
                  _RuntimeGraph(
                    title: 'Offline Queue Size',
                    keyName: 'offlineQueueSize',
                    unit: '',
                    samples: state.runtimeSamples,
                    color: Colors.brown,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return 'Paused';
    if (duration.inSeconds < 60) return '${duration.inSeconds} sec';
    return '${duration.inMinutes} min ${duration.inSeconds.remainder(60)} sec';
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;

    final spaced = value.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(0)}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static double _number(Object? value) => value is num ? value.toDouble() : 0;

  static int _integer(Object? value) => value is num ? value.toInt() : 0;
}

class _ModuleRuntimeTile extends StatelessWidget {
  final String name;
  final Map<String, dynamic> data;

  const _ModuleRuntimeTile({required this.name, required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status']?.toString() ?? 'waiting';
    final color = switch (status) {
      'running' => Colors.green,
      'error' => Colors.red,
      'disabled' => Colors.grey,
      _ => Colors.orange,
    };
    final lastExecution = data['lastExecutionAt']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 5, right: 9),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${data['decision'] ?? 'No decision'}'
                  '${lastExecution == null ? '' : ' · $lastExecution'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          StatusBadge(text: _title(status), color: color),
        ],
      ),
    );
  }

  static String _title(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _RuntimeGraph extends StatelessWidget {
  final String title;
  final String keyName;
  final String unit;
  final List<Map<String, dynamic>> samples;
  final Color color;
  final double scale;

  const _RuntimeGraph({
    required this.title,
    required this.keyName,
    required this.unit,
    required this.samples,
    required this.color,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final points = samples
        .map((sample) => sample[keyName])
        .whereType<num>()
        .map((value) => value.toDouble() * scale)
        .toList(growable: false);
    if (points.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('$title: waiting for runtime samples'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text('${points.last.toStringAsFixed(1)}$unit'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 82,
            width: double.infinity,
            child: CustomPaint(
              painter: _RuntimeLinePainter(points: points, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeLinePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  const _RuntimeLinePainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final minValue = points.reduce((a, b) => a < b ? a : b);
    final maxValue = points.reduce((a, b) => a > b ? a : b);
    final range = (maxValue - minValue).abs() < 0.0001
        ? 1.0
        : maxValue - minValue;
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? 0.0
          : index / (points.length - 1) * size.width;
      final normalized = (points[index] - minValue) / range;
      final y = size.height - normalized * (size.height - 6) - 3;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RuntimeLinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _SourceLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Value Source',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _SourceChip(source: SmartSyncDebugValueSource.live),
                _SourceChip(source: SmartSyncDebugValueSource.derived),
                _SourceChip(source: SmartSyncDebugValueSource.fallback),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E5EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final SmartSyncDebugValueSource source;

  const _MetricTile({
    required this.label,
    required this.value,
    this.detail,
    this.source = SmartSyncDebugValueSource.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                _SourceChip(source: source),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final SmartSyncDebugValueSource source;

  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      SmartSyncDebugValueSource.live => Colors.green,
      SmartSyncDebugValueSource.derived => Colors.blue,
      SmartSyncDebugValueSource.fallback => Colors.orange,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        source.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SmartSyncDebugEvent event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = switch (event.level) {
      SmartSyncDebugEventLevel.info => Colors.blueGrey,
      SmartSyncDebugEventLevel.warning => Colors.orange,
      SmartSyncDebugEventLevel.error => Colors.red,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              event.message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final String message;

  const _EmptyMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
    );
  }
}
