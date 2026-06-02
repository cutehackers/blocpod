import 'package:flutter/foundation.dart';

import 'blocpod_log_entry.dart';
import 'blocpod_log_sink.dart';

/// Log sink that writes formatted entries through Flutter's [debugPrint].
final class DebugPrintLogSink implements BlocpodLogSink {
  DebugPrintLogSink({DebugPrintCallback? debugPrintOverride}) : _debugPrint = debugPrintOverride ?? debugPrint;

  final DebugPrintCallback _debugPrint;

  @override
  void write(BlocpodLogEntry entry) {
    _debugPrint(formatBlocpodLogEntry(entry));
  }
}

/// Formats [entry] for local development logs.
String formatBlocpodLogEntry(BlocpodLogEntry entry) {
  final metadata = _safeMetadata(entry.metadata);
  final metadataText = metadata.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
  final buffer = StringBuffer()
    ..write('[${entry.level.name}] ')
    ..write(entry.timestamp.toUtc().toIso8601String())
    ..write(' ')
    ..write(entry.message);

  if (metadataText.isNotEmpty) {
    buffer
      ..write(' ')
      ..write(metadataText);
  }

  if (entry.error != null) {
    buffer
      ..write(' error=')
      ..write(entry.error);
  }

  return buffer.toString();
}

Map<String, Object?> _safeMetadata(Map<String, Object?> metadata) {
  final safe = <String, Object?>{};
  for (final MapEntry(:key, :value) in metadata.entries) {
    if (!_isSensitiveKey(key)) {
      safe[key] = _safeValue(value);
    }
  }

  return safe;
}

Object? _safeValue(Object? value) {
  if (value is Map) {
    final safe = <Object?, Object?>{};
    for (final MapEntry(:key, :value) in value.entries) {
      if (!_isSensitiveKey(key)) {
        safe[key] = _safeValue(value);
      }
    }

    return safe;
  }

  if (value is Iterable) {
    return value.map(_safeValue).toList(growable: false);
  }

  return value;
}

bool _isSensitiveKey(Object? key) {
  final normalized = key.toString().toLowerCase();
  return normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('credential') ||
      normalized.contains('password');
}
