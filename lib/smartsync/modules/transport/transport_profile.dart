import 'package:esec_bus/smartsync/models/smartsync_enums.dart';
import 'package:esec_bus/smartsync/modules/transport/transport_policy.dart';

class TransportProfile {
  final TransportType type;
  final String name;
  final TransportPolicy policy;
  final Map<String, Object?> metadata;

  const TransportProfile({
    required this.type,
    required this.name,
    required this.policy,
    this.metadata = const {},
  });

  TransportProfile copyWith({
    String? name,
    TransportPolicy? policy,
    Map<String, Object?>? metadata,
  }) {
    return TransportProfile(
      type: type,
      name: name ?? this.name,
      policy: policy ?? this.policy,
      metadata: metadata ?? this.metadata,
    );
  }
}
