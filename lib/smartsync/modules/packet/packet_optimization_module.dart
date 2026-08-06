import 'dart:convert';

import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/packet/optimized_sync_payload.dart';
import 'package:esec_bus/smartsync/modules/packet/packet_optimization_rules.dart';

class PacketOptimizationModule implements SmartSyncPacketOptimizer {
  final PacketOptimizationRules rules;

  const PacketOptimizationModule({
    this.rules = const PacketOptimizationRules.defaults(),
  });

  @override
  OptimizedSyncPayload optimize(SyncPacket packet) {
    final data = rules.compactKeys
        ? _compactPayload(packet)
        : _compatiblePayload(packet);

    return OptimizedSyncPayload(
      data: data,
      estimatedBytes: utf8.encode(jsonEncode(data)).length,
      isCompact: rules.compactKeys,
      metadataIncluded: rules.includeMetadata,
    );
  }

  Map<String, dynamic> _compactPayload(SyncPacket packet) {
    return {
      'id': packet.packetId,
      'd': packet.deviceId,
      't': packet.transportId,
      'la': _round(packet.sample.latitude, rules.coordinatePrecision),
      'lo': _round(packet.sample.longitude, rules.coordinatePrecision),
      if (packet.sample.speedMetersPerSecond != null)
        's': _round(packet.sample.speedMetersPerSecond!, rules.speedPrecision),
      if (packet.sample.headingDegrees != null)
        'h': _round(packet.sample.headingDegrees!, rules.headingPrecision),
      if (packet.sample.accuracyMeters != null)
        'a': _round(packet.sample.accuracyMeters!, rules.accuracyPrecision),
      'ts': packet.sample.capturedAt.toIso8601String(),
      if (rules.includeMetadata && packet.metadata.isNotEmpty)
        'm': Map<String, dynamic>.unmodifiable(packet.metadata),
    };
  }

  Map<String, dynamic> _compatiblePayload(SyncPacket packet) {
    return {
      'packetId': packet.packetId,
      'deviceId': packet.deviceId,
      'transportId': packet.transportId,
      'latitude': _round(packet.sample.latitude, rules.coordinatePrecision),
      'longitude': _round(packet.sample.longitude, rules.coordinatePrecision),
      if (packet.sample.speedMetersPerSecond != null)
        'speed': _round(
          packet.sample.speedMetersPerSecond!,
          rules.speedPrecision,
        ),
      if (packet.sample.headingDegrees != null)
        'heading': _round(
          packet.sample.headingDegrees!,
          rules.headingPrecision,
        ),
      if (packet.sample.accuracyMeters != null)
        'accuracy': _round(
          packet.sample.accuracyMeters!,
          rules.accuracyPrecision,
        ),
      'capturedAt': packet.sample.capturedAt.toIso8601String(),
      if (rules.includeMetadata && packet.metadata.isNotEmpty)
        'metadata': Map<String, dynamic>.unmodifiable(packet.metadata),
    };
  }

  double _round(double value, int precision) {
    return double.parse(value.toStringAsFixed(precision));
  }
}
