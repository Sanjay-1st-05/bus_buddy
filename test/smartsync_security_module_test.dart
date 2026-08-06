import 'package:esec_bus/smartsync/smartsync.dart';
import 'package:test/test.dart';

void main() {
  group('SecurityModule', () {
    final now = DateTime.utc(2026, 7, 12, 10);

    SyncPacket packet({String deviceId = 'device-1'}) {
      return SyncPacket(
        packetId: 'packet-1',
        deviceId: deviceId,
        transportId: 'BUS_01',
        sample: LocationSample(
          latitude: 11.0168,
          longitude: 76.9558,
          capturedAt: now,
        ),
      );
    }

    SecurityCredentials credentials({
      String deviceId = 'device-1',
      String token = 'token-1',
    }) {
      return SecurityCredentials(
        deviceId: deviceId,
        token: token,
        signingKeyId: 'key-1',
      );
    }

    SecurityModule module({DateTime? clock}) {
      return SecurityModule(
        trustedDeviceIds: const {'device-1'},
        validTokens: const {'token-1'},
        now: () => clock ?? now,
      );
    }

    test('signs and validates a trusted request', () {
      final security = module();
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-1',
        timestamp: now,
      );

      final result = security.validate(request);

      expect(result.isValid, isTrue);
      expect(result.status, SecurityValidationStatus.valid);
      expect(request.signature, isNotEmpty);
    });

    test('rejects unknown devices', () {
      final security = module();
      final request = security.sign(
        packet: packet(deviceId: 'device-2'),
        credentials: credentials(deviceId: 'device-2'),
        nonce: 'nonce-1',
        timestamp: now,
      );

      final result = security.validate(request);

      expect(result.isValid, isFalse);
      expect(result.status, SecurityValidationStatus.invalidDevice);
      expect(result.reason, 'unknown_device');
    });

    test('rejects missing and invalid tokens', () {
      final missingTokenRequest = module().sign(
        packet: packet(),
        credentials: credentials(token: ''),
        nonce: 'nonce-1',
        timestamp: now,
      );
      final invalidTokenRequest = module().sign(
        packet: packet(),
        credentials: credentials(token: 'bad-token'),
        nonce: 'nonce-2',
        timestamp: now,
      );

      expect(
        module().validate(missingTokenRequest).status,
        SecurityValidationStatus.missingToken,
      );
      expect(
        module().validate(invalidTokenRequest).status,
        SecurityValidationStatus.invalidToken,
      );
    });

    test('rejects expired timestamps', () {
      final security = module(clock: now.add(const Duration(minutes: 10)));
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-1',
        timestamp: now,
      );

      final result = security.validate(request);

      expect(result.isValid, isFalse);
      expect(result.status, SecurityValidationStatus.expiredTimestamp);
    });

    test('rejects replayed nonces after first valid request', () {
      final security = module();
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-1',
        timestamp: now,
      );

      expect(security.validate(request).isValid, isTrue);

      final replay = security.validate(request);

      expect(replay.isValid, isFalse);
      expect(replay.status, SecurityValidationStatus.replayDetected);
    });

    test('rejects tampered packet signature', () {
      final security = module();
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-1',
        timestamp: now,
      );
      final tampered = request.copyWith(
        packet: SyncPacket(
          packetId: 'packet-1',
          deviceId: 'device-1',
          transportId: 'BUS_01',
          sample: LocationSample(
            latitude: 12.0000,
            longitude: 76.9558,
            capturedAt: now,
          ),
        ),
      );

      final result = security.validate(tampered);

      expect(result.isValid, isFalse);
      expect(result.status, SecurityValidationStatus.invalidSignature);
    });

    test('rejects mismatched request device and packet device', () {
      final security = module();
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-1',
        timestamp: now,
      );
      final tampered = request.copyWith(deviceId: 'device-2');

      final result = security.validate(tampered);

      expect(result.isValid, isFalse);
      expect(result.status, SecurityValidationStatus.tamperedPacket);
      expect(result.reason, 'device_id_mismatch');
    });

    test('replay cache expires old nonces', () {
      var clock = now;
      final cache = ReplayProtectionCache(
        retention: const Duration(minutes: 5),
        now: () => clock,
      );

      cache.remember('nonce-1');
      expect(cache.hasSeen('nonce-1'), isTrue);

      clock = now.add(const Duration(minutes: 6));
      expect(cache.hasSeen('nonce-1'), isFalse);
      expect(cache.size, 0);
    });

    test('accepts timestamps exactly at tolerance boundary', () {
      final security = module(clock: now.add(const Duration(minutes: 5)));
      final request = security.sign(
        packet: packet(),
        credentials: credentials(),
        nonce: 'nonce-boundary',
        timestamp: now,
      );

      final result = security.validate(request);

      expect(result.isValid, isTrue);
      expect(result.status, SecurityValidationStatus.valid);
    });

    test('can disable known-device and replay requirements by rule', () {
      final security = SecurityModule(
        rules: const SecurityRules(
          timestampTolerance: Duration(minutes: 5),
          requireToken: true,
          requireKnownDevice: false,
          replayProtectionEnabled: false,
        ),
        validTokens: const {'token-1'},
        now: () => now,
      );
      final request = security.sign(
        packet: packet(deviceId: 'unregistered-device'),
        credentials: credentials(deviceId: 'unregistered-device'),
        nonce: 'reusable-nonce',
        timestamp: now,
      );

      expect(security.validate(request).isValid, isTrue);
      expect(security.validate(request).isValid, isTrue);
    });
  });
}
