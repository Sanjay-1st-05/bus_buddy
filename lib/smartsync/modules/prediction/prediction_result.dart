import 'package:esec_bus/smartsync/models/location_sample.dart';

class PredictionResult {
  final bool isActive;
  final LocationSample? predictedPosition;
  final Duration? estimatedEta;
  final double confidenceScore;
  final String reason;

  const PredictionResult({
    required this.isActive,
    required this.predictedPosition,
    required this.estimatedEta,
    required this.confidenceScore,
    required this.reason,
  });

  const PredictionResult.inactive({this.reason = 'live_gps_available'})
    : isActive = false,
      predictedPosition = null,
      estimatedEta = null,
      confidenceScore = 0;
}
