class OptimizedSyncPayload {
  final Map<String, dynamic> data;
  final int estimatedBytes;
  final bool isCompact;
  final bool metadataIncluded;

  const OptimizedSyncPayload({
    required this.data,
    required this.estimatedBytes,
    required this.isCompact,
    required this.metadataIncluded,
  });
}
