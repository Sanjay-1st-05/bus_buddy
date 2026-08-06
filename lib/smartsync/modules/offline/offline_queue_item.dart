import 'package:esec_bus/smartsync/models/sync_packet.dart';
import 'package:esec_bus/smartsync/modules/offline/offline_queue_status.dart';

class OfflineQueueItem {
  final SyncPacket packet;
  final OfflineQueueStatus status;
  final DateTime queuedAt;
  final DateTime updatedAt;
  final int attemptCount;
  final String? lastError;

  const OfflineQueueItem({
    required this.packet,
    required this.status,
    required this.queuedAt,
    required this.updatedAt,
    required this.attemptCount,
    this.lastError,
  });

  String get packetId => packet.packetId;

  OfflineQueueItem copyWith({
    OfflineQueueStatus? status,
    DateTime? updatedAt,
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return OfflineQueueItem(
      packet: packet,
      status: status ?? this.status,
      queuedAt: queuedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}
