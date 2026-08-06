class RouteAwarenessRules {
  final double maxOnRouteDistanceMeters;
  final double driftDistanceMeters;
  final double unrealisticJumpMeters;
  final double stopArrivalRadiusMeters;
  final double completionRadiusMeters;

  const RouteAwarenessRules({
    required this.maxOnRouteDistanceMeters,
    required this.driftDistanceMeters,
    required this.unrealisticJumpMeters,
    required this.stopArrivalRadiusMeters,
    required this.completionRadiusMeters,
  });

  const RouteAwarenessRules.defaults()
    : maxOnRouteDistanceMeters = 100,
      driftDistanceMeters = 500,
      unrealisticJumpMeters = 2500,
      stopArrivalRadiusMeters = 80,
      completionRadiusMeters = 100;
}
