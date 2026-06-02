/// Creates an immutable snapshot of metadata values.
Map<String, Object?> snapshotMetadata(Map<String, Object?> metadata) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final MapEntry(:key, :value) in metadata.entries) key: snapshotMetadataValue(value),
  });
}

/// Creates an immutable snapshot of a nested metadata value.
Object? snapshotMetadataValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      for (final MapEntry(:key, :value) in value.entries) key: snapshotMetadataValue(value),
    });
  }

  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(snapshotMetadataValue));
  }

  return value;
}
