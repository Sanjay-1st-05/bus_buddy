enum SecurityValidationStatus {
  valid,
  invalidDevice,
  missingToken,
  invalidToken,
  expiredTimestamp,
  replayDetected,
  invalidSignature,
  tamperedPacket,
}
