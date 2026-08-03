import 'blocpod_log_encoder.dart';
import 'blocpod_log_entry.dart';
import 'log_value_normalizer.dart';

/// Verbosity for [PrettyLogEncoder].
enum PrettyLogDetail {
  /// Prints only the primary message line plus error output when present.
  compact,

  /// Appends available diagnostic metadata on following lines.
  verbose,
}

/// Encodes structured log entries as deterministic human-readable text.
final class PrettyLogEncoder implements BlocpodLogEncoder {
  /// Creates a pretty log encoder.
  const PrettyLogEncoder({this.detail = PrettyLogDetail.compact});

  final PrettyLogDetail detail;

  static const int _maxDepth = 8;

  @override
  String encode(BlocpodLogEntry entry) {
    final buffer = StringBuffer()
      ..write(_formatUtcTime(entry.timestamp))
      ..write(' ')
      ..write(entry.level.name.toUpperCase().padRight(5))
      ..write(' ')
      ..write(_singleLineText(entry.message));

    if (detail == PrettyLogDetail.verbose) {
      final diagnostics = <String?>[
        _formatSequenceAndTrace(entry),
        _formatAttributes(entry),
      ];

      for (final diagnostic in diagnostics) {
        if (diagnostic != null && diagnostic.isNotEmpty) {
          buffer
            ..write('\n')
            ..write('  ')
            ..write(diagnostic);
        }
      }
    }

    if (entry.error != null) {
      _appendIndentedLines(buffer, _formatError(entry.error!));
    }

    if (entry.stackTrace != null) {
      _appendIndentedLines(buffer, safeLogText(entry.stackTrace!));
    }

    return buffer.toString();
  }
}

String _formatUtcTime(DateTime timestamp) {
  return timestamp.toUtc().toIso8601String().substring(11);
}

String _singleLineText(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', r'\n');
}

String? _formatSequenceAndTrace(BlocpodLogEntry entry) {
  final parts = <String>[];

  if (entry.sequence != null) {
    parts.add('sequence=${entry.sequence}');
  }

  final trace = switch ((entry.traceId, entry.spanId)) {
    (final String traceId, final String spanId) => '$traceId/$spanId',
    (final String traceId, null) => traceId,
    (null, final String spanId) => spanId,
    (null, null) => null,
  };

  if (trace != null) {
    parts.add('trace=$trace');
  }

  if (entry.parentSpanId != null) {
    parts.add('parent=${entry.parentSpanId}');
  }

  if (parts.isEmpty) {
    return null;
  }

  return parts.join(' ');
}

String? _formatAttributes(BlocpodLogEntry entry) {
  if (entry.attributes.isEmpty) {
    return null;
  }

  final normalized = normalizeLogValue(
    entry.attributes,
    maxDepth: PrettyLogEncoder._maxDepth,
  );
  return 'attributes=${_formatNormalizedValue(normalized)}';
}

String _formatNormalizedValue(Object? value) {
  if (value == null) {
    return 'null';
  }

  if (value is Map<Object?, Object?>) {
    final entries = value.entries.map(
      (entry) => '${entry.key}: ${_formatNormalizedValue(entry.value)}',
    );
    return '{${entries.join(', ')}}';
  }

  if (value is Iterable<Object?>) {
    final values = value.map(_formatNormalizedValue);
    return '[${values.join(', ')}]';
  }

  return value.toString();
}

String _formatError(Object error) {
  final type = error.runtimeType.toString();
  final text = safeLogText(error);

  if (text == type || text.startsWith('$type:')) {
    return text;
  }

  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  if (lines.isEmpty) {
    return type;
  }

  return <String>['$type: ${lines.first}', ...lines.skip(1)].join('\n');
}

void _appendIndentedLines(StringBuffer buffer, String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  for (final line in lines) {
    if (line.isEmpty) {
      continue;
    }
    buffer
      ..write('\n')
      ..write('  ')
      ..write(line);
  }
}
