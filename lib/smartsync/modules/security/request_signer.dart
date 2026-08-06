import 'dart:convert';

import 'package:esec_bus/smartsync/models/sync_packet.dart';

class RequestSigner {
  const RequestSigner();

  String sign({
    required SyncPacket packet,
    required String token,
    required String nonce,
    required DateTime timestamp,
    required String signingKeyId,
  }) {
    final canonical = canonicalPayload(
      packet: packet,
      token: token,
      nonce: nonce,
      timestamp: timestamp,
      signingKeyId: signingKeyId,
    );
    return _fnv1a64(canonical);
  }

  bool verify({
    required SyncPacket packet,
    required String token,
    required String nonce,
    required DateTime timestamp,
    required String signingKeyId,
    required String signature,
  }) {
    return sign(
          packet: packet,
          token: token,
          nonce: nonce,
          timestamp: timestamp,
          signingKeyId: signingKeyId,
        ) ==
        signature;
  }

  String canonicalPayload({
    required SyncPacket packet,
    required String token,
    required String nonce,
    required DateTime timestamp,
    required String signingKeyId,
  }) {
    final payload = <String, Object?>{
      'deviceId': packet.deviceId,
      'nonce': nonce,
      'packet': _canonicalMap(packet.toCompactJson()),
      'signingKeyId': signingKeyId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'token': token,
      'transportId': packet.transportId,
    };

    return jsonEncode(_canonicalMap(payload));
  }

  Map<String, Object?> _canonicalMap(Map<String, Object?> input) {
    final sortedKeys = input.keys.toList()..sort();
    return {
      for (final key in sortedKeys)
        key: input[key] is Map<String, Object?>
            ? _canonicalMap(input[key]! as Map<String, Object?>)
            : input[key],
    };
  }

  String _fnv1a64(String input) {
    var hash = BigInt.parse('14695981039346656037');
    final prime = BigInt.parse('1099511628211');
    final mask = (BigInt.one << 64) - BigInt.one;

    for (final byte in utf8.encode(input)) {
      hash = hash ^ BigInt.from(byte);
      hash = (hash * prime) & mask;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
