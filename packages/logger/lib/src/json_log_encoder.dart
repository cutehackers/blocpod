import 'dart:convert';

import 'blocpod_log_encoder.dart';
import 'blocpod_log_entry.dart';
import 'log_value_normalizer.dart';

/// Encodes structured log entries as one-line JSON records.
final class JsonLogEncoder implements BlocpodLogEncoder {
  /// Creates a JSON log encoder.
  const JsonLogEncoder({this.maxDepth = 8}) : assert(maxDepth > 0);

  /// Maximum recursive depth for nested values.
  final int maxDepth;

  @override
  String encode(BlocpodLogEntry entry) {
    try {
      final timestamp = entry.timestamp.toUtc().toIso8601String();
      return jsonEncode(<String, Object?>{
        'schema': 'blocpod.log',
        'schemaVersion': 1,
        'timestamp': timestamp,
        if (entry.sequence != null) 'sequence': entry.sequence,
        'level': entry.level.name,
        'message': entry.message,
        if (entry.traceId != null || entry.spanId != null || entry.parentSpanId != null)
          'trace': <String, Object?>{
            if (entry.traceId != null) 'traceId': entry.traceId,
            if (entry.spanId != null) 'spanId': entry.spanId,
            if (entry.parentSpanId != null) 'parentSpanId': entry.parentSpanId,
          },
        if (entry.attributes.isNotEmpty) 'attributes': normalizeLogAttributes(entry.attributes, maxDepth: maxDepth),
        if (entry.error != null || entry.stackTrace != null)
          'error': <String, Object?>{
            if (entry.error != null) 'type': entry.error.runtimeType.toString(),
            if (entry.error != null) 'message': safeLogText(entry.error!),
            if (entry.stackTrace != null) 'stackTrace': safeLogText(entry.stackTrace!),
          },
      });
    } catch (_) {
      final fallbackTimestamp = _safeTimestamp(entry.timestamp);
      return jsonEncode(<String, Object?>{
        'schema': 'blocpod.log',
        'schemaVersion': 1,
        'timestamp': fallbackTimestamp,
        'level': 'error',
        'message': 'Blocpod log encoding failed',
      });
    }
  }
}

String _safeTimestamp(DateTime timestamp) {
  try {
    return timestamp.toUtc().toIso8601String();
  } catch (_) {
    return DateTime.now().toUtc().toIso8601String();
  }
}
