class ReplayProtectionCache {
  final Duration retention;
  final DateTime Function() _now;
  final Map<String, DateTime> _seenNonces = {};

  ReplayProtectionCache({
    this.retention = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool hasSeen(String nonce) {
    cleanup();
    return _seenNonces.containsKey(nonce);
  }

  void remember(String nonce) {
    cleanup();
    _seenNonces[nonce] = _now();
  }

  void cleanup() {
    final now = _now();
    _seenNonces.removeWhere((_, seenAt) => now.difference(seenAt) > retention);
  }

  int get size {
    cleanup();
    return _seenNonces.length;
  }
}
