import 'dart:collection';

Object? normalizeLogValue(Object? value, {required int maxDepth}) {
  return _normalizeLogValue(
    value,
    maxDepth: maxDepth,
    depth: 1,
    activePath: HashSet<Object>.identity(),
  );
}

String safeLogText(Object value) {
  try {
    return value.toString();
  } catch (_) {
    return '<${value.runtimeType}>';
  }
}

Object? _normalizeLogValue(
  Object? value, {
  required int maxDepth,
  required int depth,
  required HashSet<Object> activePath,
}) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }

  if (value is double) {
    if (value.isNaN) {
      return 'NaN';
    }
    if (value == double.infinity) {
      return 'Infinity';
    }
    if (value == double.negativeInfinity) {
      return '-Infinity';
    }
    return value;
  }

  if (value is num) {
    return value.isFinite ? value : safeLogText(value);
  }

  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }

  if (value is Duration) {
    return value.inMicroseconds;
  }

  if (value is Enum) {
    return value.name;
  }

  if (value is Map) {
    if (activePath.contains(value)) {
      return '<cycle>';
    }
    if (depth >= maxDepth) {
      return '<max-depth-exceeded>';
    }

    activePath.add(value);
    try {
      final normalized = <String, Object?>{};
      for (final MapEntry(:key, :value) in value.entries) {
        normalized[safeLogText(key)] = _normalizeLogValue(
          value,
          maxDepth: maxDepth,
          depth: depth + 1,
          activePath: activePath,
        );
      }
      return normalized;
    } finally {
      activePath.remove(value);
    }
  }

  if (value is Iterable) {
    if (activePath.contains(value)) {
      return '<cycle>';
    }
    if (depth >= maxDepth) {
      return '<max-depth-exceeded>';
    }

    activePath.add(value);
    try {
      return value
          .map(
            (element) => _normalizeLogValue(
              element,
              maxDepth: maxDepth,
              depth: depth + 1,
              activePath: activePath,
            ),
          )
          .toList(growable: false);
    } finally {
      activePath.remove(value);
    }
  }

  return safeLogText(value);
}
