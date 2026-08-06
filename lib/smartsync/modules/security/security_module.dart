import 'package:esec_bus/smartsync/interfaces/smartsync_interfaces.dart';
import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/security/replay_protection_cache.dart';
import 'package:esec_bus/smartsync/modules/security/request_signer.dart';
import 'package:esec_bus/smartsync/modules/security/security_credentials.dart';
import 'package:esec_bus/smartsync/modules/security/security_rules.dart';
import 'package:esec_bus/smartsync/modules/security/security_validation_result.dart';
import 'package:esec_bus/smartsync/modules/security/security_validation_status.dart';
import 'package:esec_bus/smartsync/modules/security/signed_sync_request.dart';

class SecurityModule implements SmartSyncSecurityManager {
  final SecurityRules rules;
  final RequestSigner signer;
  final ReplayProtectionCache replayCache;
  final Set<String> trustedDeviceIds;
  final Set<String> validTokens;
  final DateTime Function() _now;

  SecurityModule({
    this.rules = const SecurityRules.defaults(),
    this.signer = const RequestSigner(),
    ReplayProtectionCache? replayCache,
    Set<String> trustedDeviceIds = const {},
    Set<String> validTokens = const {},
    DateTime Function()? now,
  }) : replayCache = replayCache ?? ReplayProtectionCache(now: now),
       trustedDeviceIds = Set.unmodifiable(trustedDeviceIds),
       validTokens = Set.unmodifiable(validTokens),
       _now = now ?? DateTime.now;

  @override
  SignedSyncRequest sign({
    required SyncPacket packet,
    required SecurityCredentials credentials,
    required String nonce,
    DateTime? timestamp,
  }) {
    final requestTimestamp = timestamp ?? _now();
    final signature = signer.sign(
      packet: packet,
      token: credentials.token,
      nonce: nonce,
      timestamp: requestTimestamp,
      signingKeyId: credentials.signingKeyId,
    );

    return SignedSyncRequest(
      packet: packet,
      deviceId: credentials.deviceId,
      token: credentials.token,
      nonce: nonce,
      signature: signature,
      signingKeyId: credentials.signingKeyId,
      timestamp: requestTimestamp,
    );
  }

  @override
  SecurityValidationResult validate(SignedSyncRequest request) {
    if (request.deviceId != request.packet.deviceId) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.tamperedPacket,
        reason: 'device_id_mismatch',
      );
    }

    if (rules.requireKnownDevice &&
        !trustedDeviceIds.contains(request.deviceId)) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.invalidDevice,
        reason: 'unknown_device',
      );
    }

    if (rules.requireToken && request.token.trim().isEmpty) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.missingToken,
        reason: 'missing_token',
      );
    }

    if (validTokens.isNotEmpty && !validTokens.contains(request.token)) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.invalidToken,
        reason: 'invalid_token',
      );
    }

    if (_isExpired(request.timestamp)) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.expiredTimestamp,
        reason: 'expired_timestamp',
      );
    }

    if (rules.replayProtectionEnabled && replayCache.hasSeen(request.nonce)) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.replayDetected,
        reason: 'replay_detected',
      );
    }

    final signatureValid = signer.verify(
      packet: request.packet,
      token: request.token,
      nonce: request.nonce,
      timestamp: request.timestamp,
      signingKeyId: request.signingKeyId,
      signature: request.signature,
    );
    if (!signatureValid) {
      return const SecurityValidationResult.invalid(
        status: SecurityValidationStatus.invalidSignature,
        reason: 'invalid_signature',
      );
    }

    if (rules.replayProtectionEnabled) {
      replayCache.remember(request.nonce);
    }

    return const SecurityValidationResult.valid();
  }

  bool _isExpired(DateTime timestamp) {
    final difference = _now().difference(timestamp).abs();
    return difference > rules.timestampTolerance;
  }
}
