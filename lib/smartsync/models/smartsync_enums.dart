enum NetworkQuality { excellent, good, average, weak, offline }

enum MovementType { stopped, moving, accelerating, turning, idle, parked }

enum BatteryMode { normal, balanced, powerSaving, emergencySaving }

enum SyncAction {
  sendNow,
  wait,
  queueOffline,
  retry,
  drop,
  emergencySend,
  predict,
}

enum TransportType {
  collegeBus,
  schoolBus,
  employeeShuttle,
  publicBus,
  ambulance,
  deliveryVehicle,
  taxi,
  logisticsFleet,
  agriculturalVehicle,
  autonomousVehicle,
}

enum HealthSeverity { info, warning, error, critical }
