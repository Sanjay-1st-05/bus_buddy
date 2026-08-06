import 'package:esec_bus/smartsync/models/sync_packet.dart';

class SignedSyncRequest {
  final SyncPacket packet;
  final String deviceId;
  final String token;
  final String nonce;
  final String signature;
  final String signingKeyId;
  final DateTime timestamp;

  const SignedSyncRequest({
    required this.packet,
    required this.deviceId,
    required this.token,
    required this.nonce,
    required this.signature,
    required this.signingKeyId,
    required this.timestamp,
  });

  SignedSyncRequest copyWith({
    SyncPacket? packet,
    String? deviceId,
    String? token,
    String? nonce,
    String? signature,
    String? signingKeyId,
    DateTime? timestamp,
  }) {
    return SignedSyncRequest(
      packet: packet ?? this.packet,
      deviceId: deviceId ?? this.deviceId,
      token: token ?? this.token,
      nonce: nonce ?? this.nonce,
      signature: signature ?? this.signature,
      signingKeyId: signingKeyId ?? this.signingKeyId,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
