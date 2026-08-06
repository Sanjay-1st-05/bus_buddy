class LocationSample {
  final double latitude;
  final double longitude;
  final double? speedMetersPerSecond;
  final double? headingDegrees;
  final double? accuracyMeters;
  final DateTime capturedAt;

  const LocationSample({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.speedMetersPerSecond,
    this.headingDegrees,
    this.accuracyMeters,
  });

  bool get hasValidCoordinates {
    if (latitude == 0.0 && longitude == 0.0) return false;
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }
}
