import 'package:esec_bus/smartsync/models/location_sample.dart';

class PredictionInput {
  final LocationSample previousGps;
  final DateTime predictionTime;
  final bool hasLiveGps;
  final double? roadHeadingDegrees;
  final List<LocationSample> historicalMovement;
  final double? distanceToDestinationMeters;

  const PredictionInput({
    required this.previousGps,
    required this.predictionTime,
    this.hasLiveGps = false,
    this.roadHeadingDegrees,
    this.historicalMovement = const [],
    this.distanceToDestinationMeters,
  });
}
