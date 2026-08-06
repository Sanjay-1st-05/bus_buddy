import 'location_sample.dart';

class SyncPacket {
  final String packetId;
  final String deviceId;
  final String transportId;
  final LocationSample sample;
  final Map<String, dynamic> metadata;

  const SyncPacket({
    required this.packetId,
    required this.deviceId,
    required this.transportId,
    required this.sample,
    this.metadata = const {},
  });

  Map<String, dynamic> toCompactJson() {
    return {
      'id': packetId,
      'd': deviceId,
      't': transportId,
      'la': double.parse(sample.latitude.toStringAsFixed(6)),
      'lo': double.parse(sample.longitude.toStringAsFixed(6)),
      if (sample.speedMetersPerSecond != null) 's': sample.speedMetersPerSecond,
      if (sample.headingDegrees != null) 'h': sample.headingDegrees,
      if (sample.accuracyMeters != null) 'a': sample.accuracyMeters,
      'ts': sample.capturedAt.toIso8601String(),
    };
  }
}
